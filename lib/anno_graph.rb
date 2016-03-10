# encoding: utf-8

# Copyright © 2014-2016 Lennart Bierkandt <post@lennartbierkandt.de>
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

require 'json.rb'
require_relative 'search_module.rb'
require_relative 'nlp_module.rb'

class NodeOrEdge
	include SearchableNodeOrEdge

	attr_reader :graph
	attr_accessor :attr, :type

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		self.to_h.to_json(*a)
	end

	# alternative getter for @attr hash
	def [](key)
		@attr[key]
	end

	# alternative setter for @attr hash
	def []=(key, value)
		@attr[key] = value
	end

	def cat
		@attr['cat']
	end

	def cat=(arg)
		@attr['cat'] = arg
	end

	# accessor method for the public/neutral annotations of self
	def public_attr
		@attr.public
	end

	# accessor method for the private annotations of self
	def private_attr(annotator_name)
		annotator = @graph.get_annotator(:name => annotator_name)
		@attr.private[annotator] || {}
	end

	def annotate(attributes, log_step = nil)
		log_step.add_change(:action => :update, :element => self, :attr => attributes) if log_step
		@attr.annotate_with(attributes).remove_empty!
	end
end

class Node < NodeOrEdge
	include SearchableNode

	attr_accessor :id, :in, :out, :start, :end

	# initializes node
	# @param h [{:graph => Graph, :id => String, :attr => Hash}]
	def initialize(h)
		@graph = h[:graph]
		@id = h[:id]
		@in = []
		@out = []
		@type = h[:type]
		@attr = Attributes.new(h.merge(:host => self))
		@start= h[:start]
		@end  = h[:end]
		@custom = h[:custom]
	end

	def inspect
		"Node#{@id}"
	end

	# @return [Hash] the node transformed into a hash
	def to_h
		h = {
			:id     => @id,
			:type   => @type,
			:start  => @start,
			:end    => @end,
			:custom => @custom,
		}.merge(@attr.to_h).compact
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
		Array.new(@out).each(&:delete)
		Array.new(@in).each(&:delete)
		@graph.nodes.delete(@id)
	end

	# returns nodes connected to self by ingoing edges which fulfil the (optional) block
	# @param &block [Proc] only edges for which &block evaluates to true are taken into account; if no block is given, alls edges are considered
	# @return [Array] list of found parent nodes
	def parent_nodes(&block)
		selected = @in.select(&block)
		selected = @in if selected.is_a?(Enumerator)
		return selected.map(&:start)
	end

	# returns nodes connected to self by outgoing edges which fulfil the (optional) block
	# @param &block [Proc] only edges for which &block evaluates to true are taken into account; if no block is given, alls edges are considered
	# @return [Array] child nodes connected by edges with the defined attributes
	def child_nodes(&block)
		selected = @out.select(&block)
		selected = @out if selected.is_a?(Enumerator)
		return selected.map(&:end)
	end

	# returns all token nodes that are dominated by self, or connected to self via the given link (in their linear order)
	# @param link [String] a query language string describing the link from self to the tokens that will be returned
	# @return [Array] all dominated tokens or all tokens connected via given link
	def tokens(link = nil)
		case @type
		when 'a'
	 		link = 'edge+' unless link
			self.nodes(link, 'token').sort_by(&:tokenid)
		when 't'
			[self]
		when 's'
			sentence_tokens
		when 'p'
			sentence_nodes.map(&:tokens).flatten
		end
	end

	# like tokens method, but returns text string represented by tokens
	# @param link [String] a query language string describing the link from self to the tokens whose text will be returned
	# @return [String] the text formed by all dominated tokens or all tokens connected via given link
	def text(link = nil)
		self.tokens(link).map(&:token) * ' '
	end

	# @return [Node] the sentence node self is associated with
	def sentence
		if @type == 's'
			self
		elsif @type == 'p'
			nil
		else
			parent_nodes{|e| e.type == 's'}[0]
		end
	end

	# @return [Array] the sentence nodes self dominates
	def sentence_nodes
		if @type == 'p'
			nodes = [self]
			loop do
				children = nodes.map{|n| n.child_nodes{|e| e.type == 'p'}}.flatten
				return @graph.sentence_nodes & nodes if children.empty? # use "&"" to preserve sentence order
				nodes = children
			end
		elsif @type == 's'
			[self]
		else
			[]
		end
	end

	# @return [Array] the tokens of the sentence self belongs to
	def sentence_tokens
		s = sentence
		if @type == 't'
			ordered_sister_nodes{|t| t.sentence === s}
		elsif @type == 's'
			if first_token = child_nodes{|e| e.type == 's'}.select{|n| n.type == 't'}[0]
				if first_token.speaker
					child_nodes{|e| e.type == 's'}.select{|n| n.type == 't'}.sort{|a, b| a.start <=> b.start}
				else
					first_token.ordered_sister_nodes{|t| t.sentence === s}
				end
			else
				[]
			end
		elsif @type == 'p'
			sentence_nodes.map(&:sentence_tokens).flatten
		else
			s.sentence_tokens
		end
	end

	def speaker
		if @type == 'sp'
			self
		else
			parent_nodes{|e| e.type == 'sp'}[0]
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
		sentence_tokens.map(&:token) * ' '
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

	# @param link [String] a link in query language
	# @param end_node_condition [String] an attribute description in query language to filter the returned nodes
	# @return [Array] when no link is given: the nodes associated with the sentence node self; when link is given: the nodes connected to self via given link
	def nodes(link = nil, end_node_condition = '')
		if link
			super
		else
			if @type == 'p' || @type == 's'
				sentence_nodes.map{|s| s.child_nodes{|e| e.type == 's'}}.flatten
			else
				sentence.nodes
			end
		end
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

	# the level of a section node: sentence nodes have level 0, parents of sentence nodes level 1 etc.
	# @return [Integer] the level
	def sectioning_level
		if @type == 's'
			0
		elsif @type == 'p'
			child_nodes{|e| e.type == 'p'}.map(&:sectioning_level).max + 1
		else
			nil
		end
	end

	# @return [Array] the descendant sections of self
	def descendant_sections
		if sectioning_level > 0
			children = child_nodes{|e| e.type == 'p'}
			return children + children.map(&:descendant_sections).flatten
		else
			return []
		end
	end

	# @return [Array] an ordered list of the sections that are on the same level as self
	def same_level_sections
		@graph.section_structure_nodes[sectioning_level]
	end

	# return true if the sentences self contains are before and after the sentences the other section contains;
	# in this case, the other section has to be dominated by self
	# @param other [Node] the other section
	# @return [Boolean] whether the other section's sentences are comprised
	def comprise_section?(other)
		all_sentence_nodes = @graph.sentence_nodes
		return all_sentence_nodes.index(sentence_nodes.first) < all_sentence_nodes.index(other.sentence_nodes.first) &&
			all_sentence_nodes.index(sentence_nodes.last) > all_sentence_nodes.index(other.sentence_nodes.last)
	end
end

class Edge < NodeOrEdge
	attr_accessor :id, :start, :end

	# initializes edge, registering it with start and end node
	# @param h [{:graph => Graph, :id => String, :start => Node or String, :end => Node or String, :attr => Hash}]
	def initialize(h)
		@graph = h[:graph]
		@id = h[:id]
		@type = h[:type]
		@custom  = h[:custom]
		if h[:start].is_a?(Node)
			@start = h[:start]
		else
			@start = @graph.nodes[h[:start]]
		end
		if h[:end].is_a?(Node)
			@end = h[:end]
		else
			@end = @graph.nodes[h[:end]]
		end
		@attr = Attributes.new(h.merge(:host => self))
		if @start && @end
			# register in start and end node as outgoing or ingoing edge, respectively
			@start.out << self
			@end.in << self
		else
			raise 'edge needs start and end node'
		end
	end

	# deletes self from graph and from out and in lists of start and end node
	# @param log_step [Step] optionally a log step to which the changes will be logged
	# @return [Edge] self
	def delete(log_step = nil)
		if log_step
			log_step.add_change(:action => :delete, :element => self)
		end
		@start.out.delete(self) if @start
		@end.in.delete(self) if @end
		@graph.edges.delete(@id)
	end

	# @return [Hash] the edge transformed into a hash
	def to_h
		h = {
			:start  => @start.id,
			:end    => @end.id,
			:id     => @id,
			:type   => @type,
			:custom => @custom,
		}.merge(@attr.to_h).compact
	end

	def inspect
		"Edge#{@id}"
	end

	# sets the start node of self
	# @param node [Node] the new start node
	def start=(node)
		if node
			if @start
				@start.out.delete(self)
				node.out << self
			end
			@start = node
		end
	end

	# sets the end node of self
	# @param node [Node] the new end node
	def end=(node)
		if node
			if @end
				@end.in.delete(self)
				node.in << self
			end
			@end = node
		end
	end

	def fulfil?(condition)
		return false unless @type == 'a'
		super
	end
end

class AnnoGraph
	include SearchableGraph

	attr_reader :nodes, :edges, :highest_node_id, :highest_edge_id, :annotators, :current_annotator, :file_settings
	attr_accessor :conf, :makros_plain, :makros, :info, :tagset, :anno_makros

	# initializes empty graph
	def initialize
		clear
	end

	# adds a graph in hash format to self
	# @param h [Hash] the graph to be added in hash format
	def add_hash(h)
		h['nodes'].each do |n|
			self.add_node(n.merge(:raw => true))
		end
		h['edges'].each do |e|
			self.add_edge(e.merge(:raw => true))
		end
	end

	# organizes ids for new nodes or edges
	# @param h [Hash] hash from which the new element is generated
	# @param element_type [Symbol] :node or :edge
	def new_id(h, element_type)
		case element_type
		when :node
			if !h[:id]
				h[:id] = (@highest_node_id += 1)
			else
				@highest_node_id = h[:id] if h[:id] > @highest_node_id
			end
		when :edge
			if !h[:id]
				h[:id] = (@highest_edge_id += 1)
			else
				@highest_edge_id = h[:id] if h[:id] > @highest_edge_id
			end
		end
	end

	# returns the edges that start at the given start node and end at the given end node; optionally, a block can be specified that the edges must fulfil
	# @param start_node [Node] the start node
	# @param end_node [Node] the end node
	# @param &block [Proc] only edges for which &block evaluates to true are taken into account; if no block is given, alls edges are returned
	# @return [Array] the edges found
	def edges_between(start_node, end_node, &block)
		edges = start_node.out && end_node.in
		result = edges.select(&block)
		result = edges if result.is_a?(Enumerator)
		return result
	end

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		self.to_h.to_json(*a)
	end

	# reads a graph JSON file into self, clearing self before
	# @param path [String] path to the JSON file
	def read_json_file(path)
		puts 'Reading file "' + path + '" ...'
		self.clear

		file = open(path, 'r:utf-8')
		data = JSON.parse(file.read)
		file.close
		version = data['version'].to_i
		# 'knoten' -> 'nodes', 'kanten' -> 'edges'
		if version < 4
			data['nodes'] = data.delete('knoten')
			data['edges'] = data.delete('kanten')
		end
		(data['nodes'] + data['edges']).each do |el|
			el.replace(el.symbolize_keys)
			el[:id] = el[:ID] if version < 7
			# IDs as integer
			if version < 9
				el[:id] = el[:id].to_i
				el[:start] = el[:start].to_i if el[:start].is_a?(String)
				el[:end] = el[:end].to_i if el[:end].is_a?(String)
			end
		end
		@annotators = (data['annotators'] || []).map{|a| Annotator.new(a.symbolize_keys.merge(:graph => self))}
		self.add_hash(data)
		@anno_makros = data['anno_makros'] || {}
		@info = data['info'] || {}
		@tagset = Tagset.new(data['allowed_anno'] || data['tagset'])
		@file_settings = (data['file_settings'] || {}).symbolize_keys
		@conf = AnnoGraphConf.new(data['conf'])
		create_layer_makros
		@makros_plain += data['search_makros'] || []
		@makros += parse_query(@makros_plain * "\n")['def']

		# ggf. Format aktualisieren
		if version < 7
			puts 'Updating graph format ...'
			# Attribut 'typ' -> 'cat', 'namespace' -> 'sentence', Attribut 'elementid' entfernen
			(@nodes.values + @edges.values).each do |k|
				if version < 2
					if k.attr.public['typ']
						k.attr.public['cat'] = k.attr.public.delete('typ')
					end
					if k.attr.public['namespace']
						k.attr.public['sentence'] = k.attr.public.delete('namespace')
					end
					k.attr.public.delete('elementid')
					k.attr.public.delete('edgetype')
				end
				if version < 5
					k.attr.public['f-layer'] = 't' if k.attr.public['f-ebene'] == 'y'
					k.attr.public['s-layer'] = 't' if k.attr.public['s-ebene'] == 'y'
					k.attr.public.delete('f-ebene')
					k.attr.public.delete('s-ebene')
				end
				if version < 7
					# introduce node types
					if k.kind_of?(Node)
						if k.token
							k.type = 't'
						elsif k.attr.public['cat'] == 'meta'
							k.type = 's'
							k.attr.public.delete('cat')
						else
							k.type = 'a'
						end
					else
						k.type = 'o' if k.type == 't'
						k.type = 'a' if k.type == 'g'
						k.attr.public.delete('sentence')
					end
					k.attr.public.delete('tokenid')
				end
			end
			if version < 2
				# SectNode für jeden Satz
				sect_nodes = @nodes.values.select{|k| k.type == 's'}
				@nodes.values.map{|n| n.attr.public['sentence']}.uniq.each do |s|
					if sect_nodes.select{|k| k.attr.public['sentence'] == s}.empty?
						add_node(:type => 's', :attr => {'sentence' => s}, :raw => true)
					end
				end
			end
			if version < 7
				# OrderEdges and SectEdges for SectNodes
				sect_nodes = @nodes.values.select{|n| n.type == 's'}.sort_by{|n| n.attr.public['sentence']}
				sect_nodes.each_with_index do |s, i|
					add_order_edge(:start => sect_nodes[i - 1], :end => s) if i > 0
					s.name = s.attr.public.delete('sentence')
					@nodes.values.select{|n| n.attr.public['sentence'] == s.name}.each do |n|
						n.attr.public.delete('sentence')
						add_sect_edge(:start => s, :end => n)
					end
				end
			end
		end

		puts 'Read "' + path + '".'

		return data
	end

	# serializes self in a JSON file
	# @param path [String] path to the JSON file
	# @param compact [Boolean] write compact JSON?
	# @param additional [Hash] data that should be added to the saved json in the form {:key => <data_to_be_saved>}, where data_to_be_save has to be convertible to JSON
	def write_json_file(path, compact = false, additional = {})
		puts 'Writing file "' + path + '"...'
		hash = self.to_h.merge(additional)
		json = compact ? hash.to_json : JSON.pretty_generate(hash, :indent => ' ', :space => '')
		File.open(path, 'w') do |file|
			file.write(json.encode('UTF-8'))
		end
		puts 'Wrote "' + path + '".'
	end

	# creates a new node and adds it to self
	# @param h [{:type => String, :attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Node] the new node
	def add_node(h)
		new_id(h, :node)
		@nodes[h[:id]] = Node.new(h.merge(:graph => self))
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

	# creates a new part node and adds it to self
	# @param h [{:attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Node] the new node
	def add_part_node(h)
		h.merge!(:attr => {}) unless h[:attr]
		h[:attr].merge!('name' => h[:name]) if h[:name]
		n = add_node(h.merge(:type => 'p'))
		h[:log].add_change(:action => :create, :element => n) if h[:log]
		return n
	end

	# creates a new speaker node and adds it to self
	# @param h [{:attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Node] the new node
	def add_speaker_node(h)
		h.merge!(:attr => {}) unless h[:attr]
		add_node(h.merge(:type => 'sp'))
	end

	# creates a node that is a clone (including ID) of the given node; useful for creating subcorpora
	# @param node [Node] the node to be cloned
	# @return [Node] the new node
	def add_cloned_node(node)
		add_node(node.to_h.merge(:raw => true))
	end

	# creates a new edge and adds it to self
	# @param h [{:type => String, :start => Node, :end => Node, :attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Edge] the new edge
	def add_edge(h)
		return nil unless h[:start] && h[:end]
		new_id(h, :edge)
		@edges[h[:id]] = Edge.new(h.merge(:graph => self))
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

	# creates a new part edge and adds it to self
	# @param h [{:start => Node, :end => Node, :attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Edge] the new edge
	def add_part_edge(h)
		e = add_edge(h.merge(:type => 'p'))
		h[:log].add_change(:action => :create, :element => e) if h[:log]
		return e
	end

	# creates a new speaker edge and adds it to self
	# @param h [{:start => Node, :end => Node, :attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Edge] the new edge
	def add_speaker_edge(h)
		add_edge(h.merge(:type => 'sp'))
	end

	# creates an edge that is a clone (without ID; start and end nodes via id) of the given edge; useful for creating subcorpora
	# @param node [Edge] the edge to be cloned
	# @return [Edge] the new edge
	def add_cloned_edge(edge)
		add_edge(edge.to_h.except(:id).merge(:raw => true))
	end

	# creates a new annotation node as parent node for the given nodes
	# @param nodes [Array] the nodes that will be connected to the new node
	# @param node_attrs [Hash] the annotations for the new node
	# @param edge_attrs [Hash] the annotations for the new edges
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def add_parent_node(nodes, node_attrs, edge_attrs, log_step = nil)
		sentence = nodes.map(&:sentence).most_frequent
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
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def add_child_node(nodes, node_attrs, edge_attrs, log_step = nil)
		sentence = nodes.map(&:sentence).most_frequent
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
	# @param edge [Edge] the edge to be replaced
	# @param attrs [Hash] the annotations for the new node
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def insert_node(edge, attrs, log_step = nil)
		new_node = add_anno_node(
			:attr => attrs,
			:sentence => edge.end.sentence,
			:log => log_step
		)
		add_anno_edge(
			{
				:start => edge.start,
				:end => new_node,
				:raw => true,
				:log => log_step
			}.merge(edge.attr.to_h)
		)
		add_anno_edge(
			{
				:start => new_node,
				:end => edge.end,
				:raw => true,
				:log => log_step
			}.merge(edge.attr.to_h)
		)
		edge.delete(log_step)
	end

	# deletes a node and connects its outgoing edges to its parents or its ingoing edges to its children
	# @param node [Node] the node to be deleted
	# @param mode [Symbol] :in or :out - whether to delete the ingoing or outgoing edges
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def delete_and_join(node, mode, log_step = nil)
		node.in.select{|e| e.type == 'a'}.each do |in_edge|
			node.out.select{|e| e.type == 'a'}.each do |out_edge|
				devisor = mode == :in ? out_edge : in_edge
				add_anno_edge(
					{
						:start => in_edge.start,
						:end => out_edge.end,
						:raw => true,
						:log => log_step
					}.merge(devisor.attr.to_h)
				)
			end
		end
		node.delete(log_step)
	end

	# create a section node as parent of the given section nodes
	# @param list [Array] the section nodes that are to be grouped under the new node
	# @param log_step [Step] optionally a log step to which the changes will be logged
	# @return [Node] the new section node
	def build_section(list, log_step = nil)
		# create node only when all given nodes are on the same level and none is already grouped under another section
		if list.group_by{|n| n.sectioning_level}.keys.length > 1
			raise 'All given sections have to be on the same level!'
		elsif list.map{|n| n.parent_nodes{|e| e.type == 'p'}}.flatten != []
			raise 'Given sections already belong to another section!'
		elsif !list.map{|sect| sect.same_level_sections.index(sect)}.sort.each_cons(2).all?{|a, b| b == a + 1}
			raise 'Sections have to be contiguous!'
		else
			section_node = add_part_node(:log => log_step)
			list.each do |child_node|
				add_part_edge(
					:start => section_node,
					:end => child_node,
					:log => log_step
				)
			end
			if parent = section_nodes.select{|n| n.comprise_section?(section_node)}[0]
				add_part_edge(
					:start => parent,
					:end => section_node,
					:log => log_step
				)
			end
			return section_node
		end
	end

	# deletes the given sections if allowed
	def remove_sections(list, log_step = nil)
		raise 'You cannot remove sentences' if list.any?{|s| s.type == 's'}
		if list.any?{|s| s.parent_nodes{|e| e.type == 'p'}[0] && s.parent_nodes{|e| e.type == 'p'}[0].comprise_section?(s)}
			raise 'You cannot remove sections from the middle of a containing section'
		end
		if list.any?{|s| s.parent_nodes{|e| e.type == 'p'}[0].sentence_nodes == s.sentence_nodes}
			raise 'You cannot remove intermediate sections'
		end
		list.each{|s| s.delete(log_step)}
	end

	# @return [Hash] the graph in hash format with version number and settings: {:nodes => [...], :edges => [...], :version => String, ...}
	def to_h
		{
			:nodes => @nodes.values.map(&:to_h),
			:edges => @edges.values.map(&:to_h)
		}.
			merge(:version => 9).
			merge(:conf => @conf.to_h.reject{|k,v| k == :font}).
			merge(:info => @info).
			merge(:anno_makros => @anno_makros).
			merge(:tagset => @tagset).
			merge(:annotators => @annotators).
			merge(:file_settings => @file_settings).
			merge(:search_makros => @makros_plain)
	end

	def inspect
		'Graph'
	end

	# merges another graph into self
	# @param other [Graph] the graph to be merged
	def merge!(other)
		s_nodes = sentence_nodes
		last_old_sentence_node = s_nodes.last
		new_nodes = {}
		other.nodes.each do |id,n|
			new_nodes[id] = add_node(n.to_h.merge(:id => nil))
		end
		other.edges.each do |id,e|
			if new_nodes[e.start.id] and new_nodes[e.end.id]
				add_edge(e.to_h.merge(:start => new_nodes[e.start.id], :end => new_nodes[e.end.id], :id => nil))
			end
		end
		first_new_sentence_node = @nodes.values.select{|n| n.type == 's' and !s_nodes.include?(n)}[0].ordered_sister_nodes.first
		add_order_edge(:start => last_old_sentence_node, :end => first_new_sentence_node)
		@conf.merge!(other.conf)
		@annotators += other.annotators.select{|a| !@annotators.map(&:name).include?(a.name) }
	end

	# builds a clone of self, but does not clone the nodes and edges
	# @return [Graph] the clone
	def clone
		new_graph = AnnoGraph.new
		return new_graph.clone_graph(self)
	end

	# makes self a clone of another graph
	def clone_graph(other_graph)
		@nodes = other_graph.nodes.clone
		@edges = other_graph.edges.clone
		@highest_node_id = other_graph.highest_node_id
		@highest_edge_id = other_graph.highest_edge_id
		clone_graph_info(other_graph)
		return self
	end

	# sets own settings to those of another graph
	def clone_graph_info(other_graph)
		@conf = other_graph.conf.clone
		@info = other_graph.info.clone
		@tagset = other_graph.tagset.clone
		@annotators = other_graph.annotators.clone
		@anno_makros = other_graph.anno_makros.clone
		@makros_plain = other_graph.makros_plain.clone
		@makros = parse_query(@makros_plain * "\n")['def']
	end

	# builds a subcorpus (as new graph) from a list of sentence nodes
	# @param sentence_list [Array] a list of sentence nodes
	# @return [Graph] the new graph
	def subcorpus(sentence_list)
		# create new graph
		g = AnnoGraph.new
		g.clone_graph_info(self)
		last_sentence_node = nil
		# copy speaker nodes
		@nodes.values.select{|n| n.type == 'sp'}.each do |speaker|
			g.add_cloned_node(speaker)
		end
		# copy sentence nodes and their associated nodes
		sentence_list.each do |s|
			ns = g.add_cloned_node(s)
			g.add_order_edge(:start => last_sentence_node, :end => ns) if last_sentence_node
			last_sentence_node = ns
			s.nodes.each do |n|
				nn = g.add_cloned_node(n)
				g.add_sect_edge(:start => ns, :end => nn)
			end
		end
		# copy edges
		nodes = sentence_list.map(&:nodes).flatten
		edges = nodes.map{|n| n.in + n.out}.flatten.uniq
		edges.reject{|e| e.type == 's'}.each do |e|
			g.add_cloned_edge(e)
		end
		return g
	end

	# @return [Array] an ordered list of self's sentence nodes
	def sentence_nodes
		if first_sentence_node = @nodes.values.select{|n| n.type == 's'}[0]
			first_sentence_node.ordered_sister_nodes
		else
			[]
		end
	end

	# @return [Array] all section nodes (i.e. type s and p)
	def section_nodes
		section_structure_nodes.flatten
	end

	# @return [Array] a list of ordered lists of self's section nodes, starting with the lowest level, enriched with additional information
	def section_structure
		level = 0
		result = [sentence_nodes.each_with_index.map{|n, i| {:node => n, :first => i, :last => i, :text => n.text}}]
		loop do
			next_level_sections = result[level].map do |s|
				parent = s[:node].parent_nodes{|e| e.type == 'p'}[0]
				s.merge(:node => parent)
			end
			next_level = {}
			next_level_sections.each do |s|
				next unless s[:node]
				if next_level[s[:node]]
					next_level[s[:node]][:last] = s[:last]
				else
				 next_level[s[:node]] = s
				end
			end
			unless next_level.empty?
				result << next_level.values
				level += 1
			else
				break
			end
		end
		return result
	end

	# @return [Array] a list of ordered lists of self's section nodes, starting with the lowest level
	def section_structure_nodes
		section_structure.map{|level| level.map{|sect| sect[:node]}}
	end

	# @param sections [Array] a list of section nodes of the same level
	# @return [Array] the ancestor and descendant sections of the given sections, grouped by level, starting with sentence level
	def sections_hierarchy(sections)
		return nil unless sections.map{|n| n.sectioning_level}.uniq.length == 1
		hierarchy = [sections]
		# get ancestors
		current = sections
		loop do
			parents = current.map{|n| n.parent_nodes{|e| e.type == 'p'}}.flatten.uniq
			if parents.empty?
				break
			else
				hierarchy << parents
				current = parents
			end
		end
		# get descendants
		current = sections
		loop do
			children = current.map{|n| n.child_nodes{|e| e.type == 'p'}}.flatten.uniq
			if children.empty?
				break
			else
				hierarchy.unshift(children)
				current = children
			end
		end
		return hierarchy
	end

	def speaker_nodes
		@nodes.values.select{|n| n.type == 'sp'}
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

	# clear all nodes and edges from self, reset layer configuration and search makros
	def clear
		@nodes = {}
		@edges = {}
		@highest_node_id = 0
		@highest_edge_id = 0
		@conf = AnnoGraphConf.new
		@info = {}
		@tagset = Tagset.new
		@annotators = []
		@current_annotator = nil
		@anno_makros = {}
		@file_settings = {}
		create_layer_makros
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
	# @param name [String] The name of the file
	def export_config(name)
		Dir.mkdir('exports/config') unless File.exist?('exports/config')
		File.open("exports/config/#{name}.config.json", 'w') do |f|
			f.write(JSON.pretty_generate(@conf, :indent => ' ', :space => '').encode('UTF-8'))
		end
	end

	# export tagset as JSON file for import in other graphs
	# @param name [String] The name of the file
	def export_tagset(name)
		Dir.mkdir('exports/tagset') unless File.exist?('exports/tagset')
		File.open("exports/tagset/#{name}.tagset.json", 'w') do |f|
			f.write(JSON.pretty_generate(@tagset, :indent => ' ', :space => '').encode('UTF-8'))
		end
	end

	# export annotators as JSON file for import in other graphs
	# @param name [String] The name of the file
	def export_annotators(name)
		Dir.mkdir('exports/annotators') unless File.exist?('exports/annotators')
		File.open("exports/annotators/#{name}.annotators.json", 'w') do |f|
			f.write(JSON.pretty_generate(@annotators, :indent => ' ', :space => '').encode('UTF-8'))
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
	# @param name [String] The name of the file
	def import_tagset(name)
		File.open("exports/tagset/#{name}.tagset.json", 'r:utf-8') do |f|
			@tagset = Tagset.new(JSON.parse(f.read))
		end
	end

	# loads allowed annotations from JSON file
	# @param name [String] The name of the file
	def import_annotators(name)
		File.open("exports/annotators/#{name}.annotators.json", 'r:utf-8') do |f|
			@annotators = JSON.parse(f.read).map{|a| Annotator.new(a.symbolize_keys.merge(:graph => self))}
		end
	end

	# filter a hash of attributes to be annotated; let only attributes pass that are allowed
	# @param attr [Hash] the attributes to be annotated
	# @return [Hash] the allowed attributes
	def allowed_attributes(attr)
		@tagset.allowed_attributes(attr)
	end

	def set_annotator(h)
		@current_annotator = get_annotator(h)
	end

	def get_annotator(h)
		@annotators.select{|a| h.all?{|k, v| a.send(k).to_s == v.to_s}}[0]
	end

	# delete the given annotators and all their annotations
	# @param annotators [Array of Annotators or Annotator] the annotator(s) to be deleted
	def delete_annotators(annotators)
		(@nodes.values + @edges.values).each do |element|
			annotators.each do |annotator|
				element.attr.delete_private(annotator)
			end
		end
		@annotators -= annotators
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
			:name => @name,
			:attr => @attr,
			:shortcut => @shortcut,
			:color => @color,
			:weight => @weight
		}
	end
end

class AnnoGraphConf
	attr_accessor :font, :default_color, :token_color, :found_color, :filtered_color, :edge_weight, :layers, :combinations

	def initialize(h = {})
		h ||= {}
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
		new_conf.layers = @layers.map(&:clone)
		new_conf.combinations = @combinations.map(&:clone)
		return new_conf
	end

	def merge!(other)
		other.layers.each do |layer|
			unless @layers.map(&:attr).include?(layer.attr)
				@layers << layer
			end
		end
		other.combinations.each do |combination|
			unless @combinations.map(&:attr).include?(combination.attr)
				@combinations << combination
			end
		end
	end

	def to_h
		{
			:font => @font,
			:default_color => @default_color,
			:token_color => @token_color,
			:found_color => @found_color,
			:filtered_color => @filtered_color,
			:edge_weight => @edge_weight,
			:layers => @layers.map(&:to_h),
			:combinations => @combinations.map(&:to_h)
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
		self.map(&:to_h)
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
		{:key => @key, :values => values_string}
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
		return true if value.nil? || @values == []
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

class Annotator
	attr_accessor :id, :name, :info

	def initialize(h)
		@graph = h[:graph]
		@name = h[:name] || ''
		@info = h[:info] || ''
		@id = (h[:id] || new_id).to_i
	end

	def new_id
		id_list = @graph.annotators.map(&:id)
		id = 1
		id += 1 while id_list.include?(id)
		return id
 	end

	def to_h
		{
			:id => @id,
			:name => @name,
			:info => @info,
		}
	end

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		self.to_h.to_json(*a)
	end
end
