# encoding: utf-8

# Copyright © 2014-2017 Lennart Bierkandt <post@lennartbierkandt.de>
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

class Graph
	include GraphSearch
	include GraphPersistence
	include ToolboxImporter
	include PaulaExporter
	include SaltExporter

	attr_reader :nodes, :edges, :highest_node_id, :highest_edge_id, :node_index, :annotators, :current_annotator, :file_settings, :media
	attr_accessor :conf, :makros_plain, :makros, :info, :tagset, :anno_makros

	# initializes empty graph
	def initialize
		clear
	end

	# clear all nodes and edges from self, reset layer configuration and search makros
	def clear
		@nodes = {}
		@edges = {}
		@highest_node_id = 0
		@highest_edge_id = 0
		@node_index = Hash.new{|h, k| h[k] = {}}
		@path = nil
		@multifile = nil
		@info = {}
		@conf = GraphConf.new
		@tagset = Tagset.new(self)
		@annotators = []
		@current_annotator = nil
		@anno_makros = {}
		@file_settings = {}
		@media = nil
		@messages = []
		set_makros
		GC.start
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
	# @return [Array] the edges found
	def edges_between(start_node, end_node)
		return [] unless start_node && end_node
		start_node.out && end_node.in
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
		n.annotate(h[:anno])
		e = add_sect_edge(:start => h[:sentence], :end => n) if h[:sentence]
		if h[:log]
			h[:log].add_change(:action => :create, :element => n)
			h[:log].add_change(:action => :create, :element => e) if e
		end
		return n
	end

	# creates a new token node and adds it to self
	# @param h [{:attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Node] the new node
	def add_token_node(h)
		n = add_node(h.merge(:type => 't'))
		n.annotate(h[:anno])
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
		h[:attr] ||= {}
		h[:attr].merge!('name' => h[:name]) if h[:name]
		n = add_node(h.merge(:type => 's'))
		h[:log].add_change(:action => :create, :element => n) if h[:log]
		return n
	end

	# creates a new part node and adds it to self
	# @param h [{:attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Node] the new node
	def add_part_node(h)
		h[:attr] ||= {}
		h[:attr].merge!('name' => h[:name]) if h[:name]
		n = add_node(h.merge(:type => 'p'))
		h[:log].add_change(:action => :create, :element => n) if h[:log]
		return n
	end

	# creates a new speaker node and adds it to self
	# @param h [{:attr => Hash, :id => String}] :attr and :id are optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically
	# @return [Node] the new node
	def add_speaker_node(h)
		h[:attr] ||= {}
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
		e.annotate(h[:anno])
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

	# creates a new node but doesn't add it to self so the graph doesn't know it
	# @param h [{:type => String, :attr => Hash}] :attr is optional; the id should only be used for reading in serialized graphs, otherwise the ids are cared for automatically	# @return [Node] the new node
	# @return [Node] the new node
	def create_phantom_node(h)
		Node.new(h.merge(:graph => self))
	end

	# creates a new edge but doesn't add it to self so the graph doesn't know it
	# @param h [{:type => String, :start => Node, :end => Node, :attr => Hash}] :attr is optional
	# @return [Edge] the new edge
	def create_phantom_edge(h)
		Edge.new(h.merge(:graph => self, :phantom => true))
	end

	# creates a new annotation node as parent node for the given nodes
	# @param nodes [Array] the nodes that will be connected to the new node
	# @param h [{:node_attr => Hash, :edge_attr => Hash, :layers => AnnoLayer or Array, :sentence => Node, :log => Step}]
	def add_parent_node(nodes, h = {})
		parent_node = add_anno_node(
			:anno => h[:node_anno],
			:layers => h[:layers],
			:sentence => h[:sentence],
			:log => h[:log]
		)
		nodes.each do |n|
			add_anno_edge(
				:start => parent_node,
				:end => n,
				:anno => h[:edge_anno],
				:layers => h[:layers],
				:log => h[:log]
			)
		end
	end

	# creates a new annotation node as child node for the given nodes
	# @param nodes [Array] the nodes that will be connected to the new node
	# @param h [{:node_attr => Hash, :edge_attr => Hash, :layers => AnnoLayer or Array, :sentence => Node, :log => Step}]
	def add_child_node(nodes, h = {})
		child_node = add_anno_node(
			:anno => h[:node_anno],
			:layers => h[:layers],
			:sentence => h[:sentence],
			:log => h[:log]
		)
		nodes.each do |n|
			add_anno_edge(
				:start => n,
				:end => child_node,
				:anno => h[:edge_anno],
				:layers => h[:layers],
				:log => h[:log]
			)
		end
	end

	# replaces the given edge by a sequence of an edge, a node and another edge. The new edges inherit the annotations of the replaced edge.
	# @param edge [Edge] the edge to be replaced
	# @param h [{:attr => Hash, :layers => AnnoLayer or Array, :sentence => Node, :log => Step}]
	def insert_node(edge, h = {})
		new_node = add_anno_node(h)
		add_anno_edge(
			{
				:start => edge.start,
				:end => new_node,
				:raw => true,
				:layers => edge.layers,
				:log => h[:log]
			}.merge(edge.attr.to_h)
		)
		add_anno_edge(
			{
				:start => new_node,
				:end => edge.end,
				:raw => true,
				:layers => edge.layers,
				:log => h[:log]
			}.merge(edge.attr.to_h)
		)
		edge.delete(:log => h[:log])
	end

	# deletes a node and connects its outgoing edges to its parents or its ingoing edges to its children
	# @param node [Node] the node to be deleted
	# @param mode [Symbol] :in or :out - whether to delete the ingoing or outgoing edges
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def delete_and_join(node, mode, log_step = nil)
		node.in.of_type('a').each do |in_edge|
			node.out.of_type('a').each do |out_edge|
				devisor = mode == :in ? out_edge : in_edge
				add_anno_edge(
					{
						:start => in_edge.start,
						:end => out_edge.end,
						:raw => true,
						:layers => devisor.layers,
						:log => log_step
					}.merge(devisor.attr.to_h)
				)
			end
		end
		node.delete(:log => log_step)
	end

	# builds sentence nodes from a list of names and inserts them after the given sentence node
	# @param sentence_before [Node] the sentence after which the new sentences are inserted
	# @param log_step [Step] optionally a log step to which the changes will be logged
	# @return [Array] the new sentence nodes
	def insert_sentences(sentence_before, names, log_step = nil)
		new_nodes = []
		names.each do |name|
			new_nodes << add_sect_node(:name => name, :log => log_step)
			add_order_edge(:start => new_nodes[-2], :end => new_nodes.last, :log => log_step)
		end
		if sentence_before
			sentence_after = sentence_before.node_after
			edges_between(sentence_before, sentence_after).of_type('o').each{|e| e.delete(:log => log_step)}
			add_order_edge(:start => sentence_before, :end => new_nodes.first, :log => log_step)
			add_order_edge(:start => new_nodes.last, :end => sentence_after, :log => log_step)
			if sentence_before.parent_section
				new_nodes.each do |s|
					add_part_edge(:start => sentence_before.parent_section, :end => s, :log => log_step)
				end
			end
			if @multifile
				@multifile[:sentence_index].each do |file, file_sentences|
					if index = file_sentences.index(sentence_before)
						file_sentences.insert(index + 1, *new_nodes)
					end
				end
				rebuild_multifile_order_edges_list
			end
		end
		return new_nodes
	end

	# create a section node as parent of the given section nodes
	# @param list [Array] the section nodes that are to be grouped under the new node
	# @param log_step [Step] optionally a log step to which the changes will be logged
	# @return [Node] the new section node
	def build_section(list, log_step = nil)
		# create node only when all given nodes are on the same level and none is already grouped under another section
		if list.group_by{|n| n.sectioning_level}.keys.length > 1
			raise 'All given sections have to be on the same level!'
		elsif list.map{|n| n.parent_section}.compact != []
			raise 'Given sections already belong to another section!'
		elsif !sections_contiguous?(list)
			raise 'Sections have to be contiguous!'
		elsif sections_in_different_files?(list)
			raise 'Sections have to belong to one file!'
		else
			section_node = add_part_node(:log => log_step)
			list.each do |child_node|
				add_part_edge(
					:start => section_node,
					:end => child_node,
					:log => log_step
				)
			end
			if parent = section_nodes.find{|n| n.comprise_section?(section_node)}
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
	# @param list [Array] the sections to be removed
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def remove_sections(list, log_step = nil)
		if list.any?{|s| s.type == 's'}
			raise 'You cannot remove sentences'
		elsif list.any?{|s| s.parent_section && s.parent_section.child_sections - list == []}
			raise 'You cannot remove all sections from their containing section'
		elsif list.any?{|s| s.parent_section && s.parent_section.comprise_section?(s)}
			raise 'You cannot remove sections from the middle of their containing section'
		end
		list.each{|s| s.delete(:log => log_step)}
	end

	# adds the given sections to parent section
	# @param parent [Node] the section to which the sections should be added
	# @param list [Array] the sections to be added
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def add_sections(parent, list, log_step = nil)
		if list.any?{|s| s.sectioning_level != parent.sectioning_level - 1}
			raise 'Sections to be added have to be one level below their new parent'
		elsif list.map{|n| n.parent_section}.compact != []
			raise 'Given sections already belong to another section!'
		elsif !sections_contiguous?(list + parent.child_sections)
			raise 'Sections have to be contiguous!'
		elsif sections_in_different_files?(list + parent.child_sections)
			raise 'Sections have to belong to one file!'
		end
		list.each do |section|
			add_part_edge(:start => parent, :end => section, :log => log_step)
		end
	end

	# detaches the given sections from their parent section
	# @param list [Array] the sections to be detached
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def detach_sections(list, log_step = nil)
		if list.any?{|s| s.parent_section && s.parent_section.child_sections - list == []}
			raise 'You cannot detach all sections from their containing section'
		elsif list.any?{|s| s.parent_section && !sections_contiguous?(s.parent_section.child_sections - list)}
			raise 'You cannot detach sections from the middle of their containing section'
		end
		list.each do |section|
			section.in.of_type('p').each{|e| e.delete(:log => log_step)}
		end
	end

	# deletes the given sections including their child sections and their content
	# @param list [Array] the sections to be deleted
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def delete_sections(list, log_step = nil)
		if list.any?{|s| s.parent_section && s.parent_section.child_sections - list == []}
			raise 'You cannot delete all sections from their containing section'
		end
		list.each do |section|
				# join remaining sentences
				add_order_edge(
					:start => section.sentence_nodes.first.node_before,
					:end => section.sentence_nodes.last.node_after,
					:log => log_step
				)
			# delete dependent nodes
			if section.type == 's'
				section.nodes.each{|n| n.delete(:log => log_step)}
			else
				section.descendant_sections.each do |n|
					n.nodes.each{|n| n.delete(:log => log_step)}
					n.delete(:log => log_step)
				end
			end
			# delete the section node itself
			if @multifile && section.type == 's'
				@multifile[:sentence_index].each{|file, list| list.delete(section)}
			end
			section.delete(:log => log_step)
		end
		rebuild_multifile_order_edges_list
	end

	# true it the given sections are contiguous
	# @param sections [Array] the sections to be tested
	# @return [Boolean]
	def sections_contiguous?(sections)
		sections.map{|sect| sect.same_level_sections.index(sect)}
			.sort.each_cons(2).all?{|a, b| b == a + 1}
	end

	# true if the given sections belong to different files of a multifile corpus
	# @param sections [Array] the sections to be tested
	# @return [Boolean]
	def sections_in_different_files?(sections)
		@multifile &&
			@multifile[:sentence_index].values.none?{|file_sentences|
				(sections.map(&:sentence_nodes).flatten - file_sentences).empty?
			}
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
		first_new_sentence_node = @node_index['s'].values.find{|n| !s_nodes.include?(n)}.ordered_sister_nodes.first
		add_order_edge(:start => last_old_sentence_node, :end => first_new_sentence_node)
		@conf.merge!(other.conf)
		@annotators += other.annotators.select{|a| !@annotators.map(&:name).include?(a.name) }
	end

	# builds a clone of self, but does not clone the nodes and edges
	# @return [Graph] the clone
	def clone
		new_graph = Graph.new
		return new_graph.clone_graph(self)
	end

	# makes self a clone of another graph
	# @param other_graph [Graph] the graph to be cloned
	def clone_graph(other_graph)
		@nodes = other_graph.nodes.clone
		@edges = other_graph.edges.clone
		@highest_node_id = other_graph.highest_node_id
		@highest_edge_id = other_graph.highest_edge_id
		@node_index = other_graph.node_index.map_hash{|k, v| v.clone} # clone two levels deep
		clone_graph_info(other_graph)
		return self
	end

	# sets own settings to those of another graph
	# @param other_graph [Graph] the graph whose settings are to be cloned
	def clone_graph_info(other_graph)
		@conf = other_graph.conf.clone
		@info = other_graph.info.clone
		@tagset = other_graph.tagset.clone
		@annotators = other_graph.annotators.clone
		@current_annotator = other_graph.current_annotator
		@file_settings = other_graph.file_settings.clone
		@anno_makros = other_graph.anno_makros.clone
		set_makros(other_graph.makros_plain.clone)
	end

	# builds a subcorpus (as new graph) from a list of sentence nodes
	# @param sentence_list [Array] a list of sentence nodes
	# @return [Graph] the new graph
	def subcorpus(sentence_list)
		# create new graph
		g = Graph.new
		g.clone_graph_info(self)
		last_sentence_node = nil
		# copy speaker nodes
		@node_index['sp'].values.each do |speaker|
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
		if first_sentence_node = @node_index['s'].values[0]
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
		result = [sentence_nodes.each_with_index.map{|n, i| {:node => n, :first => i, :last => i}}]
		loop do
			next_level_sections = result[level].map do |s|
				s.merge(:node => s[:node].parent_section)
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
			break if next_level.empty?
			result << next_level.values
			level += 1
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
		return nil unless sections && sections.map{|n| n.sectioning_level}.uniq.length == 1
		hierarchy = [sections]
		# get ancestors
		current = sections
		loop do
			parents = current.map{|n| n.parent_section}.compact.uniq
			break if parents.empty?
			hierarchy << parents
			current = parents
		end
		# get descendants
		current = sections
		loop do
			children = current.map{|n| n.child_sections}.flatten.uniq
			break if children.empty?
			hierarchy.unshift(children)
			current = children
		end
		return hierarchy
	end

	# @return [Array] self's speaker nodes
	def speaker_nodes
		@node_index['sp'].values
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
		self.edges_between(last_token, next_token).of_type('o')[0].delete(:log => h[:log]) if last_token && next_token
		return token_collection
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
						t[k] = (v.is_a?(Fixnum)) ? words[i][v] : v
					end
				end
			when 'punkt'
				words = NLP.tokenize(s)
				tokens = build_tokens(words, :sentence => sentence_node)
			end
		end
	end

	# filter an array of (potential) annotations; let only annotations pass that are allowed
	# @param attr [Array] the annotations to be used
	# @return [Array] the allowed annotations
	def allowed_annotations(annotations, element)
		# add indices for tracking invalid annotations
		annotations.each_with_index{|a, i| a[:id] = i}
		# allow only annotations on element's layers
		allowed = annotations.select do |a|
			!a[:layer] ||
				@conf.layer_by_shortcut[a[:layer]] &&
				(@conf.expand_shortcut(a[:layer]) - element.layers.map(&:shortcut)).empty?
		end
		if element.type == 'a' || element.type == 't'
			# expand layerless rules
			allowed.map! do |a|
				(a[:layer] || element.layers.empty?) ? a : element.layers.map{|l| a.merge(:layer => l.shortcut)}
			end.flatten!
			# check against tagset
			allowed = @tagset.allowed_annotations(allowed, element)
		end
		# inform about invalid annotations
		invalid = (annotations.map{|a| a[:id]} - allowed.map{|a| a[:id]}).map{|id| annotations.find{|a| a[:id] == id}}
		@messages << "Illicit annotation: #{Graph.annotations_to_s(invalid)}" unless invalid.empty?
		# return allowed annotations
		allowed
	end

	# get the graph's messages and clear them
	def fetch_messages
		msg = @messages.uniq
		@messages = []
		return msg
	end

	# set the current annotator by id or name
	# @param attr [Hash] a hash with the key :id or :name
	# @return [Annotator] the current annotator
	def set_annotator(h)
		@current_annotator = get_annotator(h)
	end

	# get annotator by id or name
	# @param attr [Hash] a hash with the key :id or :name
	# @return [Annotator] the annotator with the given id or name
	def get_annotator(h)
		@annotators.find{|a| h.all?{|k, v| a.send(k).to_s == v.to_s}}
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

	# set the search makros
	# @param makro_definitions [Array] the makro definitions as strings, i.e. "def" commands
	def set_makros(makro_definitions = [])
		@makros_plain = makro_definitions
		@makros = parse_query(@makros_plain * "\n", nil)['def']
	end

	# rebuild list of order edges that connect the sentences of different files
	def rebuild_multifile_order_edges_list
		return unless @multifile
		@multifile[:order_edges] = @multifile[:sentence_index].map{|f, list|
			list.last.out.of_type('o').first
		}.compact
	end

	def self.annotations_to_s(annotations)
		annotations.map do |a|
			"#{a[:layer] ? "#{a[:layer]}:" : ''}#{a[:key]}:#{a[:value]}"
		end.join(' ')
	end
end
