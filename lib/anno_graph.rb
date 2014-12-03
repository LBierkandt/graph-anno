# encoding: utf-8

# Copyright © 2014 Lennart Bierkandt <post@lennartbierkandt.de>
#
# This file is part of GraphAnno.
#
# GraphAnno is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# GraphAnno is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with GraphAnno. If not, see <http://www.gnu.org/licenses/>.

require_relative 'graph'
require_relative 'search_module'
require_relative 'nlp_module'

class NodeOrEdge
	attr_accessor :type

	def initialize(h)
		super
		@type = h[:type]
	end

	# @return [Hash] the element transformed into a hash with all values casted to strings
	def to_h
		super.merge(:type => @type)
	end

	def cat
		@attr['cat']
	end

	def cat=(arg)
		@attr['cat'] = arg
	end

	def sentence
		@attr['sentence']
	end

	def sentence=(arg)
		@attr['sentence'] = arg
	end

	def meta
		@graph.nodes.values.select{|n| n.sentence == self.sentence && n.cat == 'meta'}[0]
	end

end

class AnnoNode < Node

	def tokens(link = nil) # liefert alle dominierten (bzw. über 'link' verbundenen) Tokens
		if !link
			if @attr['s-layer'] == 't'
				link = 'edge(s-layer:t)*'
			else
				link = 'edge(cat:ex) node(s-layer:t | token://) edge(s-layer:t)*'
			end
		end
		return self.nodes(link, 'token://').sort{|a,b| a.tokenid <=> b.tokenid}
	end

	def text(link = nil)
		self.tokens(link).map{|t| t.token} * ' '
	end

	def sentence_tokens # Alle Tokens desselben Satzes
		if @attr['token']
			tokens = [self]
			tok = self
			while tok = tok.token_before
				tokens.unshift(tok)
			end
			tok = self
			while tok = tok.token_after
				tokens.push(tok)
			end
			return tokens
		else
			return @graph.sentence_tokens(self.sentence)
		end
	end

	def sentence_text
		return self.sentence_tokens.map{|t| t.token} * ' '
	end

	def position
		if @attr['token']
			position = self.tokenid.to_f
		else
			summe = 0
			toks = self.tokens
			toks.each do |t|
				summe += t.position
			end
			if toks.length > 0
				position = summe / toks.length
			else
				position = 0
			end
		end
		return position
	end

	def position_wrt(other, stil = nil, detail = true)
		st = self.tokens
		ot = other.tokens
		r = ''
		if st == [] || ot == [] || self.sentence != other.sentence
			return 'nd'
		end
		if st & ot != []
			if st == ot
				return 'idem'
			elsif ot - st == []
				if stil == 'eq' then return 'super' elsif stil == 'dom' then else r = 'super_' end
				st = st - ot
			elsif st - ot == []
				if stil == 'eq' then return 'sub' elsif stil == 'dom' then else r = 'sub_' end
				ot = ot - st
			else
				return 'intersect'
			end
		end
		st_first = st.first.tokenid
		st_last  = st.last.tokenid
		ot_first = ot.first.tokenid
		ot_last  = ot.last.tokenid
		if st_last < ot_first
			r += 'pre'
			if detail and st_last < ot_first - 1 then r += '_separated' end
		elsif st_first > ot_last
			r +='post'
			if detail and st_first > ot_last + 1 then r += '_separated' end
		elsif st_first > ot_first && st_last < ot_last &&
			ot.any?{|t| t.tokenid < st_first || t.tokenid > st_last}
			r += 'in'
		elsif st_first < ot_first && st_last > ot_last &&
			st.any?{|t| t.tokenid < ot_first || t.tokenid > ot_last}
			r += 'circum'
		else
			r += 'interlaced'
			if detail
				if    st_first < ot_first && st_last < ot_last
					r += '_pre'
				elsif st_first > ot_first && st_last > ot_last
					r += '_post'
				elsif st_first > ot_first && st_last < ot_last
					r += '_in'
				elsif st_first < ot_first && st_last > ot_last
					r += '_circum'
				end
			end
		end
		return r
	end

	# methods specific for token nodes:

	def token
		@attr['token']
	end

	def token=(arg)
		@attr['token'] = arg
	end

	def tokenid
		self.sentence_tokens.index(self)
	end

	def token_before
		self.parent_nodes{|e| e.type == 't'}[0]
	end

	def token_after
		self.child_nodes{|e| e.type == 't'}[0]
	end

	def remove_token
		if self.token
			s = self.sentence
			if self.token_before && self.token_after
				@graph.add_edge(:type => 't', :start => self.token_before, :end => self.token_after, :attr => {'sentence' => s})
			end
			self.delete
		end
	end

end

class AnnoEdge < Edge

	def fulfil?(bedingung)
		if @type != 'g' then return false end
		super
	end

end

class AnnoGraph < SearchableGraph
	attr_accessor :conf, :makros_plain, :makros

	# extend the super class initialize method by reading in of display and layer configuration, and search makros
	def initialize
		super
		@conf = AnnoGraphConf.new
		create_layer_makros
		load_makros
	end

	# reads a graph JSON file into self, clearing self before
	# @param path [String] path to the JSON file
	def read_json_file(path)
		puts 'Reading file "' + path + '" ...'
		self.clear

		file = open(path, 'r:utf-8')
		nodes_and_edges = JSON.parse(file.read)
		file.close
		version = nodes_and_edges['version'].to_i
		# 'knoten' -> 'nodes', 'kanten' -> 'edges'
		if version < 4
			nodes_and_edges['nodes'] = nodes_and_edges['knoten']
			nodes_and_edges['edges'] = nodes_and_edges['kanten']
			nodes_and_edges.delete('knoten')
			nodes_and_edges.delete('kanten')
		end
		(nodes_and_edges['nodes'] + nodes_and_edges['edges']).each do |el|
			el.replace(Hash[el.map{|k,v| [k.to_sym, v]}])
		end
		self.add_hash(nodes_and_edges)
		if version >= 6
			@conf = AnnoGraphConf.new(nodes_and_edges['conf'])
			create_layer_makros
			@makros_plain << nodes_and_edges['search_makros']
			@makros += parse_query(@makros_plain * "\n")['def']
		end

		# ggf. Format aktualisieren
		if version < 5
			puts 'Updating graph format ...'
			# Attribut 'typ' -> 'cat', 'namespace' -> 'sentence', Attribut 'elementid' entfernen
			(@nodes.values + @edges.values).each do |k|
				if version < 2
					if k['typ']
						k['cat'] = k['typ']
						k.attr.delete('typ')
					end
					if k['namespace']
						k['sentence'] = k['namespace']
						k.attr.delete('namespace')
					end
					k.attr.delete('elementid')
				end
				if version < 5
					if k['f-ebene'] == 'y' then k['f-layer'] = 't' end
					if k['s-ebene'] == 'y' then k['s-layer'] = 't' end
					k.attr.delete('f-ebene')
					k.attr.delete('s-ebene')
				end
				if version < 7
					# introduce node types
					if k.type_of?(Node)
						if k.token
							k.type = 't'
						elsif k['cat'] == 'meta'
							k.type = 's'
							k.attr.delete('cat')
						else
							k.type = 'a'
						end
					end
				end
				k.attr.delete('tokenid')
			end
			if version < 2
				# 'meta'-Node für jeden Satz
				sect_nodes = @nodes.values.select{|k| k.type == 's'}
				self.sentences.each do |ns|
					if sect_nodes.select{|k| k.sentence == ns}.empty?
						self.add_node(:type => 's', :attr => {'sentence' => ns})
					end
				end
			end
		end

		puts 'Read "' + path + '".'
	end

	# creates a new node and adds it to self
	# @param h [{:type => String, :attr => Hash, :ID => String}] :attr and :ID are optional; the ID should only be used for reading in serialized graphs, otherwise the IDs are cared for automatically
	# @return [Node] the new node
	def add_node(h)
		new_id(h, :node)
		@nodes[h[:ID]] = AnnoNode.new(h.merge(:graph => self))
	end

	# creates a new edge and adds it to self
	# @param h [{:type => String, :start => Node, :end => Node, :attr => Hash, :ID => String}] :attr and :ID are optional; the ID should only be used for reading in serialized graphs, otherwise the IDs are cared for automatically
	# @return [Edge] the new edge
	def add_edge(h)
		new_id(h, :edge)
		@edges[h[:ID]] = AnnoEdge.new(h.merge(:graph => self))
	end

	def filter!(bedingung)
		@nodes.each do |id,node|
			if !node.fulfil?(bedingung) then @nodes.delete(id) end
		end
		@edges.each do |id,edge|
			if !edge.fulfil?(bedingung) then @edges.delete(id) end
		end
	end

	# @return [Hash] the graph in hash format with version number: {'nodes' => [...], 'edges' => [...], 'version' => String}
	def to_h
		super.
			merge('version' => '6').
			merge('conf' => @conf.to_h.reject{|k,v| k == 'font'}).
			merge('search_makros' => @makros_plain)
	end

	def merge!(other)
		super
		@conf.merge!(other.conf)
	end

	def sentences
		@nodes.values.map{|n| n.sentence}.uniq.sort
	end

	def sentence_tokens(s)
		if first_token = @nodes.values.select{|n| n.sentence == s and n.token}[0]
			return first_token.sentence_tokens
		else
			return []
		end
	end

	# builds token-nodes from a list of words, concatenates them and appends them if tokens in the given sentence are already present; if next_token is given, the new tokens are inserted before next_token
	def build_tokens(words, sentence, next_token = nil)
		token_collection = []
		if next_token
			last_token = next_token.token_before
		else
			last_token = self.sentence_tokens(sentence)[-1]
		end
		words.each do |word|
			token_collection << self.add_node(:attr => {'token' => word, 'sentence' => sentence})
		end
		# This creates relationships between the tokens in the form of 1->2->3->4
		token_collection[0..-2].each_with_index do |token, index|
			self.add_edge(:type => 't', :start => token, :end => token_collection[index+1], :attr => {'sentence' => sentence})
		end
		# If there are already tokens, append the new ones
		if last_token then self.add_edge(:type => 't', :start => last_token, :end => token_collection[0], :attr => {'sentence' => sentence}) end
		if next_token then self.add_edge(:type => 't', :start => token_collection[-1], :end => next_token, :attr => {'sentence' => sentence}) end
		if last_token && next_token then self.edges_between(last_token, next_token){|e| e.type == 't'}[0].delete end
		return token_collection
	end

	# extend clear method: reset layer configuration and search makros
	def clear
		super
		@conf = AnnoGraphConf.new
		load_makros
	end

	# import corpus from pre-formatted text
	# @param text [String] The text to be imported
	# @param options [Hash] The options for the segmentation
	def import_text(text, options)
		case options['processing_method']
		when 'regex'
			sentences = text.split(options['sentences']['sep'])
			parameters = options['tokens']['anno'].parse_parameters
			annotation = parameters[:attributes].map_hash{|k, v| v.match(/^\$\d+$/) ? v.match(/^\$(\d+)$/)[1].to_i - 1 : v}
		when 'punkt'
			sentences = NLP.segment(text, options['language'])
		end
		id_length = sentences.length.to_s.length
		sentences.each_with_index do |s, i|
			sentence_id = "%0#{id_length}d" % i
			sentence_node = add_node(:attr => {'cat' => 'meta', 'sentence' => sentence_id})
			case options['processing_method']
			when 'regex'
				words = s.scan(options['tokens']['regex'])
				tokens = build_tokens([''] * words.length, sentence_id)
				tokens.each_with_index do |t, i|
					annotation.each do |k, v|
						if v.class == Fixnum
							t[k] = words[i][v]
						else
							t[k] = v
						end
					end
				end
			when 'punkt'
				words = NLP.tokenize(s)
				tokens = build_tokens(words, sentence_id)
			end
		end
	end

	private

	def load_makros
		@makros_plain = []
		makros_strings = []
		if File.exists?('conf/search_makros.txt')
			File.open('conf/search_makros.txt', 'r:utf-8') do |datei|
				makros_strings = datei.readlines.map{|line| line.strip}
			end
		end
		@makros = parse_query(makros_strings * "\n")['def']
	end

	def create_layer_makros
		layer_makros_array = (@conf.layers_and_combinations).map do |layer|
			attributes_string = [*layer.attr].map{|a| a + ':t'} * ' & '
			"def #{layer.shortcut} #{attributes_string}"
		end
		@makros += parse_query(layer_makros_array * "\n")['def']
	end

end

class AnnoLayer
	attr_accessor :name, :attr, :shortcut, :color, :weight

	def initialize(h = {})
		@name = h['name'] || ''
		@attr = h['attr'] || ''
		@shortcut = h['shortcut'] || ''
		@color = h['color'] || '#000000'
		@weight = h['weight'] || '1'
		@graph = h['graph'] || nil
	end

	def to_h
		{
			'name' => @name,
			'attr' => @attr,
			'shortcut' => @shortcut,
			'color' => @color,
			'weight' => @weight
		}
	end
end

class AnnoGraphConf
	attr_accessor :font, :default_color, :token_color, :found_color, :filtered_color, :edge_weight, :layers, :combinations

	def initialize(h = {})
		default = File::open('conf/display.yml'){|f| YAML::load(f)}
		default.merge!(File::open('conf/layers.yml'){|f| YAML::load(f)})

		@font = h['font'] || default['font']
		@default_color = h['default_color'] || default['default_color']
		@token_color = h['token_color'] || default['token_color']
		@found_color = h['found_color'] || default['found_color']
		@filtered_color = h['filtered_color'] || default['filtered_color']
		@edge_weight = h['edge_weight'] || default['edge_weight']
		if h['layers']
			@layers = h['layers'].map{|l| AnnoLayer.new(l)}
		else
			@layers = default['layers'].map{|l| AnnoLayer.new(l)}
		end
		if h['combinations']
			@combinations = h['combinations'].map{|c| AnnoLayer.new(c)}
		else
			@combinations = default['combinations'].map{|c| AnnoLayer.new(c)}
		end
	end

	def merge!(other)
		other.layers.each do |layer|
			if not @layers.map{|l| l.attr}.include?(layer.attr)
				@layers << layer
			end
		end
		other.combinations.each do |combination|
			if not @combinations.map{|c| c.attr}.include?(combination.attr)
				@combinations << combination
			end
		end
	end

	def to_h
		{
			'font' => @font,
			'default_color' => @default_color,
			'token_color' => @token_color,
			'found_color' => @found_color,
			'filtered_color' => @filtered_color,
			'edge_weight' => @edge_weight,
			'layers' => @layers.map{|l| l.to_h},
			'combinations' => @combinations.map{|c| c.to_h}
		}
	end

	def layers_and_combinations
		@layers + @combinations
	end

	def layer_shortcuts
		layers_and_combinations.map{|l| {l.shortcut => l.name}}.reduce{|m, h| m.merge(h)}
	end

	def layer_attributes
		h = {}
		layers_and_combinations.map do |l|
			h[l.name] = [*l.attr].map{|attr| {attr => 't'}}.reduce{|m, h| m.merge(h)}
		end
		return h
	end

end

class Array

	def text
		self.map{|n| n.text} * ' '
	end

end

class String
	def parse_parameters
		str = self.strip
		h = {
			:attributes => {},
			:keys => [],
			:elements => [],
			:words => [],
			:all_nodes => [],
			:meta => [],
			:nodes => [],
			:edges => [],
			:tokens => []
		}

		r = {}
		r[:ctrl] = '(\s|:)'
		r[:bstring] = '[^\s:"]+'
		#r[:qstring] = '"(([^"]*(\\\"[^"]*)*[^\\\])|)"'
		r[:qstring] = '"([^"]*(\\\"[^"]*)*([^"\\\]|\\\"))?"'
		r[:string] = '(' + r[:qstring] + '|' + r[:bstring] + ')'
		r[:attribute] = r[:string] + ':' + r[:string] + '?'
		r.keys.each{|k| r[k] = Regexp.new('^' + r[k])}

		while str != ''
			m = nil
			if m = str.match(r[:ctrl])
			elsif m = str.match(r[:attribute])
				key = m[2] ? m[2].gsub('\"', '"') : m[1]
				val = m[6] ? m[6].gsub('\"', '"') : m[5]
				if val == nil
					h[:keys] << key
				else
					h[:attributes][key] = val
				end
			elsif m = str.match(r[:string])
				word = m[2] ? m[2].gsub('\"', '"') : m[1]
				h[:words] << word
				if word.match(/^(([ent]\d+)|m)$/)
					h[:elements] << word
					case word[0]
						when 'm'
							h[:meta] << word
						when 'n'
							h[:nodes] << word
							h[:all_nodes] << word
						when 't'
							h[:tokens] << word
							h[:all_nodes] << word
						when 'e'
							h[:edges] << word
					end
				elsif mm = word.match(/^([ent])(\d+)\.\.\1(\d+)$/)
					([mm[2].to_i, mm[3].to_i].min..[mm[2].to_i, mm[3].to_i].max).each do |n|
						h[:elements] << mm[1] + n.to_s
						case word[0]
							when 'n'
								h[:nodes] << mm[1] + n.to_s
								h[:all_nodes] << mm[1] + n.to_s
							when 't'
								h[:tokens] << mm[1] + n.to_s
								h[:all_nodes] << mm[1] + n.to_s
							when 'e'
								h[:edges] << mm[1] + n.to_s
						end
					end
				end
			else
				break
			end
			str = str[m[0].length..-1]
		end

		return h
	end

end