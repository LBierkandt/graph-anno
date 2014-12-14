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

require 'json'

class NodeOrEdge

	# getter for @attr hash
	def [](key)
		@attr[key]
	end

	# setter for @attr hash
	def []=(key, value)
		@attr[key] = value
	end

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		self.to_h.to_json(*a)
	end

end

class Node < NodeOrEdge
	attr_accessor :attr, :ID, :in, :out

	# initializes node
	# @param h [{:graph => Graph, :ID => String, :attr => Hash}]
	def initialize(h)
		@graph = h[:graph]
		@ID = h[:ID]
		if not @attr = h[:attr] then @attr = {} end
		@in = []
		@out = []
	end

	def inspect
		'Node' + @ID
	end

	# @return [Hash] the node transformed into a hash with all values casted to strings
	def to_h
		esc_attr = @attr.map_hash{|k,v| v.to_s}
		return {
			:attr => esc_attr,
			:ID   => @ID
		}
	end

	# deletes self and all in- and outgoing edges
	# @return [Node] self
	def delete
		Array.new(@out).each{|e| e.delete}
		Array.new(@in).each{|e| e.delete}
		@graph.nodes.delete(@ID)
	end

	# returns nodes connected to self by ingoing edges which fulfil the (optional) block
	# @param &block [Proc] only edges for which &block evaluates to true are taken into account; if no block is given, alls edges are considered
	# @return [Array] list of found parent nodes
	def parent_nodes(&block)
		selected = @in.select(&block)
		if selected.is_a?(Enumerator)
			selected = @in
		end
		return selected.map{|e| e.start}
	end

	# returns nodes connected to self by outgoing edges which fulfil the (optional) block
	# @param &block [Proc] only edges for which &block evaluates to true are taken into account; if no block is given, alls edges are considered
	# @return [Array] child nodes connected by edges with the defined attributes
	def child_nodes(&block)
		selected = @out.select(&block)
		if selected.is_a?(Enumerator)
			selected = @out
		end
		return selected.map{|e| e.end}
	end

end

class Edge < NodeOrEdge
	attr_accessor :attr, :ID, :start, :end

	# initializes edge, registering it with start and end node
	# @param h [{:graph => Graph, :ID => String, :start => Node or String, :end => Node or String, :attr => Hash}]
	def initialize(h)
		@graph = h[:graph]
		@ID = h[:ID]
		if h[:start].class == String
			@start = @graph.nodes[h[:start]]
		else
			@start = h[:start]
		end
		if h[:end].class == String
			@end = @graph.nodes[h[:end]]
		else
			@end = h[:end]
		end
		if not @attr = h[:attr]
			@attr = {}
		end
		if @start && @end
			# register in start and end node as outgoing or ingoing edge, respectively
			@start.out << self
			@end.in << self
		else
			self.delete
		end
	end

	# deletes self and from graph and from out and in lists of start and end node
	# @return [Edge] self
	def delete
		if @start then @start.out.delete(self) end
		if @end then @end.in.delete(self) end
		@graph.edges.delete(@ID)
	end

	# @return [Hash] the edge transformed into a hash with all values casted to strings
	def to_h
		esc_attr = @attr.map_hash{|k,v| v.to_s}
		return {
			:start => @start.ID,
			:end   => @end.ID,
			:attr  => esc_attr,
			:ID    => @ID
		}
	end

	def inspect
		'Edge' + @ID
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

end

class Graph
	protected

	attr_accessor :highest_node_ID, :highest_edge_ID
	attr_writer :nodes, :edges

	public

	attr_reader :nodes, :edges

	# initializes empty graph 
	def initialize
		@nodes = {}
		@edges = {}
		@highest_node_ID = 0
		@highest_edge_ID = 0
	end

	# builds a clone of self, but does not clone the nodes and edges
	# @return [Graph] the clone
	def clone
		new_graph = self.class.new
		new_graph.nodes = @nodes.clone
		new_graph.edges = @edges.clone
		new_graph.highest_node_ID = @highest_node_ID
		new_graph.highest_edge_ID = @highest_edge_ID
		return new_graph
	end

	def inspect
		'Graph'
	end

	# clears all nodes and edges from self
	def clear
		@nodes.clear
		@edges.clear
		@highest_node_ID = 0
		@highest_edge_ID = 0
	end

	# serializes self in a JSON file
	# @param path [String] path to the JSON file
	def write_json_file(path)
		puts 'Writing file "' + path + '"...'
		file = open(path, 'w')
		file.write(JSON.pretty_generate(self, :indent => ' ', :space => '').encode('UTF-8'))
		file.close
		puts 'Wrote "' + path + '".'
	end

	# reads a graph JSON file into self, clearing self before
	# @param path [String] path to the JSON file
	def read_json_file(path)
		puts 'Reading file "' + path + '" ...'
		self.clear
		
		file = open(path, 'r:utf-8')
		nodes_and_edges = JSON.parse(file.read)
		file.close
		(nodes_and_edges['nodes'] + nodes_and_edges['edges']).each do |el|
			el.replace(Hash[el.map{|k,v| [k.to_sym, v]}])
		end
		self.add_hash(nodes_and_edges)
		
		puts 'Read "' + path + '".'
	end

	# adds a graph in hash format to self
	# @param h [Hash] the graph to be added in hash format
	def add_hash(h)
		h['nodes'].each do |n|
			self.add_node(n)
		end
		h['edges'].each do |e|
			self.add_edge(e)
		end
	end

	# creates a new node and adds it to self
	# @param h [{:attr => Hash, :ID => String}] :attr and :ID are optional; the ID should only be used for reading in serialized graphs, otherwise the IDs are cared for automatically
	# @return [Node] the new node
	def add_node(h)
		new_id(h, :node)
		@nodes[h[:ID]] = Node.new(h.merge(:graph => self))
	end

	# creates a new edge and adds it to self
	# @param h [{:start => Node, :end => Node, :attr => Hash, :ID => String}] :attr and :ID are optional; the ID should only be used for reading in serialized graphs, otherwise the IDs are cared for automatically
	# @return [Edge] the new edge
	def add_edge(h)
		new_id(h, :edge)
		@edges[h[:ID]] = Edge.new(h.merge(:graph => self))
	end

	# organizes IDs for new nodes or edges
	# @param h [Hash] hash from which the new element is generated
	# @param element_type [Symbol] :node or :edge
	def new_id(h, element_type)
		case element_type
			when :node
				if !h[:ID]
					h[:ID] = (@highest_node_ID += 1).to_s
				else
					if h[:ID].to_i > @highest_node_ID then @highest_node_ID = h[:ID].to_i end
				end
			when :edge
				if !h[:ID]
					h[:ID] = (@highest_edge_ID += 1).to_s
				else
					if h[:ID].to_i > @highest_edge_ID then @highest_edge_ID = h[:ID].to_i end
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
		if result.is_a?(Enumerator)
			result = edges
		end
		return result
	end

	# merges self with another graph (in place)
	# @param other_graph [Graph] the graph to be added to self
	def merge!(other_graph)
		new_nodes = {}
		other_graph.nodes.each do |id,n|
			new_nodes[id] = add_node(n.to_h.merge(:ID => nil))
		end
		other_graph.edges.each do |id,e|
			if new_nodes[e.start.ID] and new_nodes[e.end.ID]
				add_edge(e.to_h.merge(:start => new_nodes[e.start.ID], :end => new_nodes[e.end.ID]))
			end
		end
	end

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		self.to_h.to_json(*a)
	end

	# @return [Hash] the graph in hash format: {'nodes' => [...], 'edges' => [...]}
	def to_h
		return {
			'nodes' => @nodes.values.map{|n| n.to_h}.reject{|n| n['ID'] == '0'},
			'edges' => @edges.values.map{|e| e.to_h}
		}
	end

end

class Hash

	# @param h2 [Hash] the hash to be tested for inclusion in self
	# @return [Boolean] true if the key-value pairs of h2 are a subset of self
	def includes(h2)
		if h2.to_h == {}
			return true
		else
			return h2.any?{|k,v| self[k] == v}
		end
	end

	# creates a new hash by applying the given block to every key-value pair of self and assigning the result as value to the unaltered key
	# @param block [Proc] the block to be applied to the key-value pairs of self
	# @return [Hash] the new Hash
	def map_hash(&block)
		self.merge(self){|k, v| block.call(k, v)}
	end

end

