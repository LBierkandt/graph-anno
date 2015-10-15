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

require_relative 'graph.rb'
require_relative 'search_module.rb'
require_relative 'nlp_module.rb'

class NodeOrEdge
	attr_accessor :type

	def cat
		@attr['cat']
	end

	def cat=(arg)
		@attr['cat'] = arg
	end

	def annotate(attr, log_step = nil)
		log_step.add_change(:action => :update, :element => self, :attr => attr) if log_step
		@attr.merge!(attr).keep_if{|k, v| v}
	end
end

class AnnoNode < Node
	def initialize(h)
		super
		@type = h[:type]
	end

	# @return [Hash] the element transformed into a hash with all values casted to strings
	def to_h
		super.merge(:type => @type)
	end

	# deletes self and all in- and outgoing edges; optionally writes changes to log
	# @param log_step [Step] optionally a log step to which the changes will be logged
	# @return [Node] self
	def delete(log_step = nil)
		if log_step
			@out.each{|e| log_step.add_change(:action => :delete, :element => e)}
			@in.each{|e| log_step.add_change(:action => :delete, :element => e)}
			log_step.add_change(:action => :delete, :element => self)
		end
		super()
	end

	# returns all token nodes that are dominated by self, or connected to self via the given link (in their linear order)
	# @param link [String] a query language string describing the link from self to the tokens that will be returned
	# @return [Array] all dominated tokens or all tokens connected via given link
	def tokens(link = nil)
 		link = 'edge+' unless link
		self.nodes(link, 'token').sort_by{|token| token.tokenid}
	end

	# like tokens method, but returns text string represented by tokens
	# @param link [String] a query language string describing the link from self to the tokens whose text will be returned
	# @return [String] the text formed by all dominated tokens or all tokens connected via given link
	def text(link = nil)
		self.tokens(link).map{|t| t.token} * ' '
	end

	# @return [Node] the sentence node self is associated with
	def sentence
		if @type == 's'
			self
		else
			parent_nodes{|e| e.type == 's'}[0]
		end
	end

	# @return [Array] the tokens of the sentence self belongs to
	def sentence_tokens
		s = sentence
		if @type == 't'
			ordered_sister_nodes{|t| t.sentence === s}
		elsif @type == 's'
			if first_token = child_nodes{|e| e.type == 's'}.select{|n| n.type == 't'}[0]
				first_token.ordered_sister_nodes{|t| t.sentence === s}
			else
				[]
			end
		else
			s.sentence_tokens
		end
	end

	# @param block [Lambda] a block to filter the considered sister nodes
	# @return [Array] an ordered list of the sister nodes of self, optionally filtered by a block
	def ordered_sister_nodes(&block)
		block ||= lambda{|n| true}
		nodes = [self]
		node = self
		while node = node.node_before(&block)
			nodes.unshift(node)
		end
		node = self
		while node = node.node_after(&block)
			nodes.push(node)
		end
		return nodes
	end

	# @return [String] the text of the sentence self belongs to
	def sentence_text
		sentence_tokens.map{|t| t.token} * ' '
	end

	# @return [Float] the position of self in terms of own tokenid or averaged tokenid of the dominated (via tokens method) tokens
	# @param link [String] a query language string describing the link from self to the tokens that will be returned
	def position(link = nil)
		if @type == 't'
			return self.tokenid.to_f
		else
			toks = self.tokens(link)
			return toks.length > 0 ? toks.reduce(0){|sum, t| sum += t.position} / toks.length : 0
		end
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
			r += '_separated' if detail and st_last < ot_first - 1
		elsif st_first > ot_last
			r +='post'
			r += '_separated' if detail and st_first > ot_last + 1
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

	def node_before(&block)
		block ||= lambda{|n| true}
		parent_nodes{|e| e.type == 'o'}.select(&block)[0]
	end

	def node_after(&block)
		block ||= lambda{|n| true}
		child_nodes{|e| e.type == 'o'}.select(&block)[0]
	end

	# methods specific for token nodes:

	# @return [String] self's text
	def token
		@attr['token']
	end

	# @param arg [String] new self's text
	def token=(arg)
		@attr['token'] = arg
	end

	# @return [Integer] position of self in ordered list of own sentence's tokens
	def tokenid
		self.sentence_tokens.index(self)
	end

	# deletes self and joins adjacent tokens if possible
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def remove_token(log_step = nil)
		if self.token
			s = self.sentence
			if self.node_before && self.node_after
				e = @graph.add_order_edge(:start => self.node_before, :end => self.node_after)
				log_step.add_change(:action => :create, :element => e) if log_step
			end
			self.delete(log_step)
		end
	end

	# methods specific for section nodes:

	# @return [String] self's name attribute
	def name
		@attr['name']
	end

	# @param name [String] self's new name attribute
	def name=(name)
		@attr['name'] = name
	end

	# @param link [String] a link in query language
	# @param end_node_condition [String] an attribute description in query language to filter the returned nodes
	# @return [Array] when no link is given: the nodes associated with the sentence node self; when link is given: the nodes connected to self via given link
	def nodes(link = nil, end_node_condition = '')
		if link
			super
		else
			if @type == 's'
				child_nodes{|e| e.type == 's'}
			else
				sentence.nodes
			end
		end
	end
end

class AnnoEdge < Edge
	def initialize(h)
		super
		@type = h[:type]
	end

	# deletes self from graph and from out and in lists of start and end node
	# @param log_step [Step] optionally a log step to which the changes will be logged
	# @return [Edge] self
	def delete(log_step = nil)
		if log_step
			log_step.add_change(:action => :delete, :element => self)
		end
		super()
	end

	# @return [Hash] the element transformed into a hash with all values casted to strings
	def to_h
		super.merge(:type => @type)
	end

	def fulfil?(condition)
		return false unless @type == 'a'
		super
	end
end

class AnnoGraph < SearchableGraph
	attr_accessor :conf, :makros_plain, :makros, :info, :allowed_anno, :anno_makros

	# extend the super class initialize method by reading in of display and layer configuration, and search makros
	def initialize
		super
		@conf = AnnoGraphConf.new
		@info = {}
		@allowed_anno = Tagset.new
		@anno_makros = {}
		create_layer_makros
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
			el[:id] = el[:ID] if version < 7
		end
		self.add_hash(nodes_and_edges)
		if version >= 6
			@anno_makros = nodes_and_edges['anno_makros'] || {}
			@info = nodes_and_edges['info'] || {}
			@allowed_anno = Tagset.new(nodes_and_edges['allowed_anno'])
			@conf = AnnoGraphConf.new(nodes_and_edges['conf'])
			create_layer_makros
			@makros_plain += nodes_and_edges['search_makros']
			@makros += parse_query(@makros_plain * "\n")['def']
		end

		# ggf. Format aktualisieren
		if version < 7
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
					if k.kind_of?(Node)
						if k.token
							k.type = 't'
						elsif k['cat'] == 'meta'
							k.type = 's'
							k.attr.delete('cat')
						else
							k.type = 'a'
						end
					else
						k.type = 'o' if k.type == 't'
						k.type = 'a' if k.type == 'g'
						k.attr.delete('sentence')
					end
					k.attr.delete('tokenid')
				end
			end
			if version < 2
				# SectNode für jeden Satz
				sect_nodes = @nodes.values.select{|k| k.type == 's'}
				@nodes.values.map{|n| n['sentence']}.uniq.each do |s|
					if sect_nodes.select{|k| k['sentence'] == s}.empty?
						add_sect_node(:name => s)
					end
				end
			end
			if version < 7
				# OrderEdges and SectEdges for SectNodes
				sect_nodes = @nodes.values.select{|n| n.type == 's'}.sort_by{|n| n['sentence']}
				sect_nodes.each_with_index do |s, i|
					add_order_edge(:start => sect_nodes[i - 1], :end => s) if i > 0
					s.name = s.attr.delete('sentence')
					@nodes.values.select{|n| n['sentence'] == s.name}.each do |n|
						n.attr.delete('sentence')
						add_sect_edge(:start => s, :end => n)
					end
				end
			end
		end

		puts 'Read "' + path + '".'
	end

	# creates a new node and adds it to self
	# @param h [{:type => String, :attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Node] the new node
	def add_node(h)
		new_id(h, :node)
		@nodes[h[:id]] = AnnoNode.new(h.merge(:graph => self))
	end

	# creates a new anno node and adds it to self
	# @param h [{:attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Node] the new node
	def add_anno_node(h)
		n = add_node(h.merge(:type => 'a'))
		e = add_sect_edge(:start => h[:sentence], :end => n) if h[:sentence]
		if h[:log]
			h[:log].add_change(:action => :create, :element => n)
			h[:log].add_change(:action => :create, :element => e)
		end
		return n
	end

	# creates a new token node and adds it to self
	# @param h [{:attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Node] the new node
	def add_token_node(h)
		n = add_node(h.merge(:type => 't'))
		e = add_sect_edge(:start => h[:sentence], :end => n) if h[:sentence]
		if h[:log]
			h[:log].add_change(:action => :create, :element => n)
			h[:log].add_change(:action => :create, :element => e)
		end
		return n
	end

	# creates a new section node and adds it to self
	# @param h [{:attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Node] the new node
	def add_sect_node(h)
		h.merge!(:attr => {}) unless h[:attr]
		h[:attr].merge!('name' => h[:name]) if h[:name]
		n = add_node(h.merge(:type => 's'))
		h[:log].add_change(:action => :create, :element => n) if h[:log]
		return n
	end

	# creates a new edge and adds it to self
	# @param h [{:type => String, :start => Node, :end => Node, :attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Edge] the new edge
	def add_edge(h)
		return nil unless h[:start] && h[:end]
		new_id(h, :edge)
		@edges[h[:id]] = AnnoEdge.new(h.merge(:graph => self))
	end

	# creates a new anno edge and adds it to self
	# @param h [{:start => Node, :end => Node, :attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Edge] the new edge
	def add_anno_edge(h)
		e = add_edge(h.merge(:type => 'a'))
		h[:log].add_change(:action => :create, :element => e) if h[:log]
		return e
	end

	# creates a new order edge and adds it to self
	# @param h [{:start => Node, :end => Node, :attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Edge] the new edge
	def add_order_edge(h)
		e = add_edge(h.merge(:type => 'o'))
		h[:log].add_change(:action => :create, :element => e) if h[:log]
		return e
	end

	# creates a new sect edge and adds it to self
	# @param h [{:start => Node, :end => Node, :attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Edge] the new edge
	def add_sect_edge(h)
		e = add_edge(h.merge(:type => 's'))
		h[:log].add_change(:action => :create, :element => e) if h[:log]
		return e
	end

	# creates a new annotation node as parent node for the given nodes
	# @param nodes [Array] the nodes that will be connected to the new node
	# @param node_attrs [Hash] the annotations for the new node
	# @param edge_attrs [Hash] the annotations for the new edges
	# @param sentence [SectNode] the sentence node to which the new node will belong
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def add_parent_node(nodes, node_attrs, edge_attrs, sentence, log_step = nil)
		parent_node = add_anno_node(
			:attr => node_attrs,
			:sentence => sentence,
			:log => log_step
		)
		nodes.each do |n|
			add_anno_edge(
				:start => parent_node,
				:end => n,
				:attr => edge_attrs,
				:log => log_step
			)
		end
	end

	# creates a new annotation node as child node for the given nodes
	# @param nodes [Array] the nodes that will be connected to the new node
	# @param node_attrs [Hash] the annotations for the new node
	# @param edge_attrs [Hash] the annotations for the new edges
	# @param sentence [SectNode] the sentence node to which the new node will belong
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def add_child_node(nodes, node_attrs, edge_attrs, sentence, log_step = nil)
		child_node = add_anno_node(
			:attr => node_attrs,
			:sentence => sentence,
			:log => log_step
		)
		nodes.each do |n|
			add_anno_edge(
				:start => n,
				:end => child_node,
				:attr => edge_attrs,
				:log => log_step
			)
		end
	end

	# replaces the given edge by a sequence of an edge, a node and another edge. The new edges inherit the annotations of the replaced edge.
	# @param edge [AnnoEdge] the edge to be replaced
	# @param attrs [Hash] the annotations for the new node
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def insert_node(edge, attrs, log_step = nil)
		new_node = add_anno_node(
			:attr => attrs,
			:sentence => edge.end.sentence,
			:log => log_step
		)
		add_anno_edge(
			:start => edge.start,
			:end => new_node,
			:attr => edge.attr.clone,
			:log => log_step
		)
		add_anno_edge(
			:start => new_node,
			:end => edge.end,
			:attr => edge.attr.clone,
			:log => log_step
		)
		edge.delete(log_step)
	end

	# deletes a node and connects its outgoing edges to its parents or its ingoing edges to its children
	# @param node [AnnoNode] the node to be deleted
	# @param mode [Symbol] :in or :out - whether to delete the ingoing or outgoing edges
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def delete_and_join(node, mode, log_step = nil)
		node.in.select{|e| e.type == 'a'}.each do |in_edge|
			node.out.select{|e| e.type == 'a'}.each do |out_edge|
				devisor = mode == :in ? out_edge : in_edge
				add_anno_edge(
					:start => in_edge.start,
					:end => out_edge.end,
					:attr => devisor.attr.clone,
					:log => log_step
				)
			end
		end
		node.delete(log_step)
	end

	# @return [Hash] the graph in hash format with version number: {'nodes' => [...], 'edges' => [...], 'version' => String}
	def to_h
		super.
			merge('version' => '7').
			merge('conf' => @conf.to_h.reject{|k,v| k == 'font'}).
			merge('info' => @info).
			merge('anno_makros' => @anno_makros).
			merge('allowed_anno' => @allowed_anno).
			merge('search_makros' => @makros_plain)
	end

	# merges another graph into self
	# @param other [Graph] the graph to be merged
	def merge!(other)
		s_nodes = sentence_nodes
		last_old_sentence_node = s_nodes.last
		super
		first_new_sentence_node = @nodes.values.select{|n| n.type == 's' and !s_nodes.include?(n)}[0].ordered_sister_nodes.first
		add_order_edge(:start => last_old_sentence_node, :end => first_new_sentence_node)
		@conf.merge!(other.conf)
	end

	# @return [Graph] a clone of self (nodes and edges are not cloned)
	def clone
		new_graph = super
		new_graph.clone_graph_info(self)
		return new_graph
	end

	# sets self's configuration to the cloned configuration of the given graph
	# @param other_graph [Graph] the other graph
	def clone_graph_info(other_graph)
		@conf = other_graph.conf.clone
		@info = other_graph.info.clone
		@allowed_anno = other_graph.allowed_anno.clone
		@makros_plain = other_graph.makros_plain.clone
		@makros = parse_query(@makros_plain * "\n")['def']
	end

	# builds a subcorpus (as new graph) from a list of sentence nodes
	# @param sentence_list [Array] a list of sentence nodes
	# @return [Graph] the new graph
	def subcorpus(sentence_list)
		nodes = sentence_list.map{|s| s.nodes}.flatten
		edges = nodes.map{|n| n.in + n.out}.flatten.uniq
		g = AnnoGraph.new
		g.clone_graph_info(self)
		last_sentence_node = nil
		sentence_list.each do |s|
			ns = g.add_sect_node(:attr => s.attr, :id => s.id)
			g.add_order_edge(:start => last_sentence_node, :end => ns) if last_sentence_node
			last_sentence_node = ns
			s.nodes.each do |n|
				nn = g.add_node(:attr => n.attr, :type => n.type, :id => n.id)
				g.add_sect_edge(:start => ns, :end => nn)
			end
		end
		edges.reject{|e| e.type == 's'}.each do |e|
			g.add_edge(:attr => e.attr, :type => e.type, :start => e.start.id, :end => e.end.id)
		end
		return g
	end

	# @return [Array] an ordered list of self's sentence nodes
	def sentence_nodes
		if first_sect_node = @nodes.values.select{|n| n.type == 's'}[0]
			first_sect_node.ordered_sister_nodes
		else
			[]
		end
	end

	# builds token nodes from a list of words, concatenates them and appends them if a sentence is given and the given sentence contains tokens; if next_token is given, the new tokens are inserted before next_token; if last_token is given, the new tokens are inserted after last_token
	# @param words [Array] a list of strings from which the new tokens will be created
	# @param h [Hash] a hash with one of the keys :sentence (a sentence node), :next_token or :last_token (a token node)
	def build_tokens(words, h)
		if h[:sentence]
			sentence = h[:sentence]
			last_token = sentence.sentence_tokens[-1]
		elsif h[:next_token]
			next_token = h[:next_token]
			last_token = next_token.node_before
			sentence = next_token.sentence
		elsif h[:last_token]
			last_token = h[:last_token]
			next_token = last_token.node_after
			sentence = last_token.sentence
		else
			return
		end
		token_collection = words.map do |word|
			add_token_node(:attr => {'token' => word}, :sentence => sentence, :log => h[:log])
		end
		# This creates relationships between the tokens in the form of 1->2->3->4
		token_collection[0..-2].each_with_index do |token, index|
			add_order_edge(:start => token, :end => token_collection[index+1], :log => h[:log])
		end
		# If there are already tokens, append the new ones
		add_order_edge(:start => last_token, :end => token_collection[0], :log => h[:log]) if last_token
		add_order_edge(:start => token_collection[-1], :end => next_token, :log => h[:log]) if next_token
		self.edges_between(last_token, next_token){|e| e.type == 'o'}[0].delete(h[:log]) if last_token && next_token
		return token_collection
	end

	# extend clear method: reset layer configuration and search makros
	def clear
		super
		@conf = AnnoGraphConf.new
		@info = {}
		@allowed_anno = Tagset.new
		@makros_plain = []
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
		sentence_node = nil
		old_sentence_node = nil
		sentences.each_with_index do |s, i|
			sentence_id = "%0#{id_length}d" % i
			sentence_node = add_sect_node(:name => sentence_id)
			add_order_edge(:start => old_sentence_node, :end => sentence_node)
			old_sentence_node = sentence_node
			case options['processing_method']
			when 'regex'
				words = s.scan(options['tokens']['regex'])
				tokens = build_tokens([''] * words.length, :sentence => sentence_node)
				tokens.each_with_index do |t, i|
					annotation.each do |k, v|
						t[k] = (v.class == Fixnum) ? words[i][v] : v
					end
				end
			when 'punkt'
				words = NLP.tokenize(s)
				tokens = build_tokens(words, :sentence => sentence_node)
			end
		end
	end

	# export corpus as SQL file for import in GraphInspect
	# @param name [String] The name of the corpus, and the name under which the file will be saved
	def export_sql(name)
		Dir.mkdir('exports/sql') unless File.exist?('exports/sql')
		# corpus
		str = "INSERT INTO `corpora` (`name`, `conf`, `makros`, `info`) VALUES\n"
		str += "('#{name.sql_json_escape_quotes}', '#{@conf.to_h.to_json.sql_json_escape_quotes}', '#{@makros_plain.to_json.sql_json_escape_quotes}', '#{@info.to_json.sql_json_escape_quotes}');\n"
		str += "SET @corpus_id := LAST_INSERT_id();\n"
		# nodes
		@nodes.values.each_slice(1000) do |chunk|
			str += "INSERT INTO `nodes` (`id`, `corpus_id`, `attr`, `type`) VALUES\n"
			str += chunk.map do |n|
				"(#{n.id}, @corpus_id, '#{n.attr.to_json.sql_json_escape_quotes}', '#{n.type}')"
			end * ",\n" + ";\n"
		end
		# edges
		@edges.values.each_slice(1000) do |chunk|
			str += "INSERT INTO `edges` (`id`, `corpus_id`, `start`, `end`, `attr`, `type`) VALUES\n"
			str += chunk.map do |e|
				"(#{e.id}, @corpus_id, '#{e.start.id}', '#{e.end.id}', '#{e.attr.to_json.sql_json_escape_quotes}', '#{e.type}')"
			end * ",\n" + ";\n"
		end
		File.open("exports/sql/#{name}.sql", 'w') do |f|
			f.write(str)
		end
	end

	# export layer configuration as JSON file for import in other graphs
	# @param name [String] The name under which the file will be saved
	def export_config(name)
		Dir.mkdir('exports/config') unless File.exist?('exports/config')
		File.open("exports/config/#{name}.config.json", 'w') do |f|
			f.write(JSON.pretty_generate(@conf, :indent => ' ', :space => '').encode('UTF-8'))
		end
	end

	# export allowed annotations as JSON file for import in other graphs
	# @param name [String] The name of the file
	def export_tagset(name)
		Dir.mkdir('exports/tagset') unless File.exist?('exports/tagset')
		File.open("exports/tagset/#{name}.tagset.json", 'w') do |f|
			f.write(JSON.pretty_generate(@allowed_anno, :indent => ' ', :space => '').encode('UTF-8'))
		end
	end

	# loads layer configurations from JSON file
	# @param name [String] The name of the file
	def import_config(name)
		File.open("exports/config/#{name}.config.json", 'r:utf-8') do |f|
			@conf = AnnoGraphConf.new(JSON.parse(f.read))
		end
	end

	# loads allowed annotations from JSON file
	# @param name [String] The name under which the file will be saved
	def import_tagset(name)
		File.open("exports/tagset/#{name}.tagset.json", 'r:utf-8') do |f|
			@allowed_anno = Tagset.new(JSON.parse(f.read))
		end
	end

	# filter a hash of attributes to be annotated; let only attributes pass that are allowed
	# @param attr [Hash] the attributes to be annotated
	# @return [Hash] the allowed attributes
	def allowed_attributes(attr)
		@allowed_anno.allowed_attributes(attr)
	end

	private

	def create_layer_makros
		@makros = []
		@makros_plain = []
		layer_makros_array = (@conf.layers_and_combinations).map do |layer|
			attributes_string = [*layer.attr].map{|a| a + ':t'} * ' & '
			"def #{layer.shortcut} #{attributes_string}"
		end
		@makros = parse_query(layer_makros_array * "\n")['def']
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

	def clone
		new_conf = super
		new_conf.layers = @layers.map{|l| l.clone}
		new_conf.combinations = @combinations.map{|c| c.clone}
		return new_conf
	end

	def merge!(other)
		other.layers.each do |layer|
			unless @layers.map{|l| l.attr}.include?(layer.attr)
				@layers << layer
			end
		end
		other.combinations.each do |combination|
			unless @combinations.map{|c| c.attr}.include?(combination.attr)
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

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		self.to_h.to_json(*a)
	end
end

class Array
	def text
		self.map{|n| n.text} * ' '
	end
end

class Tagset < Array
	def initialize(a = [])
		a.to_a.each do |rule|
			self << TagsetRule.new(rule['key'], rule['values']) if rule['key'].strip != ''
		end
	end

	def allowed_attributes(attr)
		return attr.clone if self.empty?
		attr.select do |key, value|
			self.any?{|rule| rule.key == key and rule.allowes?(value)}
		end
	end

	def to_a
		self.map{|rule| rule.to_h}
	end

	def to_json(*a)
		self.to_a.to_json(*a)
	end
end

class TagsetRule
	attr_accessor :key, :values

	def initialize(key, values)
		@key = key.strip
		@values = values.lex_ql.select{|tok| [:bstring, :qstring, :regex].include?(tok[:cl])}
	end

	def to_h
		{'key' => @key, 'values' => values_string}
	end

	def values_string
		@values.map do |tok|
			case tok[:cl]
			when :bstring
				tok[:str]
			when :qstring
				'"' + tok[:str] + '"'
			when :regex
				'/' + tok[:str] + '/'
			end
		end * ' '
	end

	def allowes?(value)
		return true if value.nil?
		@values.any? do |rule|
			case rule[:cl]
			when :bstring, :qstring
				value == rule[:str]
			when :regex
				value.match('^' + rule[:str] + '$')
			end
		end
	end
end

class String
	def parse_parameters
		str = self.strip
		h = {
			:string => str,
			:attributes => {},
			:elements => [],
			:words => [],
			:all_nodes => [],
			:meta => [],
			:nodes => [],
			:edges => [],
			:tokens => [],
			:ids => [],
		}

		r = {}
		r[:ctrl] = '(\s|:)'
		r[:comment] = '#'
		r[:bstring] = '[^\s:"#]+'
		#r[:qstring] = '"(([^"]*(\\\"[^"]*)*[^\\\])|)"'
		r[:qstring] = '"([^"]*(\\\"[^"]*)*([^"\\\]|\\\"))?"'
		r[:string] = '(' + r[:qstring] + '|' + r[:bstring] + ')'
		r[:attribute] = r[:string] + ':' + r[:string] + '?'
		r[:id] = '@' + '[_[:alnum:]]+'
		r.keys.each{|k| r[k] = Regexp.new('^' + r[k])}

		while str != ''
			m = nil
			if m = str.match(r[:comment])
				break
			elsif m = str.match(r[:ctrl])
			elsif m = str.match(r[:attribute])
				key = m[2] ? m[2].gsub('\"', '"') : m[1]
				val = m[6] ? m[6].gsub('\"', '"') : m[5]
				h[:attributes][key] = val
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
				elsif word.match(r[:id])
					h[:ids] << word
				end
			else
				break
			end
			str = str[m[0].length..-1]
		end

		return h
	end

	def sql_json_escape_quotes
		self.gsub("'", "\\\\'").gsub('\\"', '\\\\\\"')
	end
end