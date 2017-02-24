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

require 'htmlentities.rb'
require_relative 'dot_graph.rb'

class GraphView
	attr_reader :tokens, :nodes, :edges, :i_nodes
	attr_accessor :filter, :show_refs

	def initialize(controller)
		@ctrl = controller
		@tokens = []
		@nodes = []
		@edges = []
		@i_nodes = []
		@filter = {:mode => 'unfilter'}
		@show_refs = true
	end

	def generate
		set_section_info

		set_elements
		apply_filter

		create_dot_graphs
		create_tokens
		create_nodes
		create_edges

		return @section_info.merge(:dot => @viz_graph)
	end

	private

	def set_elements
		@i_nodes = @ctrl.graph.node_index['a'].values.select{|n| !n.sentence}
		if @ctrl.current_sections
			@tokens = @ctrl.current_sections.map(&:sentence_tokens).flatten
			sentence_nodes = @ctrl.current_sections.map(&:nodes).flatten
			sentence_edges = sentence_nodes.map{|n| n.in + n.out}.flatten.uniq
			all_nodes = sentence_edges.map{|e| [e.start, e.end]}.flatten.uniq
			all_edges = (all_nodes.map{|n| n.in}.flatten & all_nodes.map{|n| n.out}.flatten).uniq
			@nodes = all_nodes.of_type('a')
			@edges = all_edges.of_type('a')
			@order_edges = all_edges.of_type('o')
		else
			@tokens = []
			@nodes = @i_nodes
			@edges = (@i_nodes.map{|n| n.in}.flatten & @i_nodes.map{|n| n.out}.flatten).uniq
			@order_edges = []
		end
	end

	def apply_filter
		if @filter[:mode] == 'filter'
			@nodes.select!{|n| @filter[:show] == n.fulfil?(@filter[:cond])}
			@edges.select!{|e| @filter[:show] == e.fulfil?(@filter[:cond])}
		end
	end

	def set_section_info
		@section_info = {:textline => '', :meta => ''}
		if @ctrl.current_sections
			if @ctrl.current_sections.length == 1
				@section_info[:meta] = build_label(@ctrl.current_sections.first)
			end
		else
			@section_info[:textline] = 'Independent nodes'
		end
	end

	def create_dot_graphs
		graph_options = {
			:type => :digraph,
			:rankdir => :TB,
			:use => :dot,
			:ranksep => 0.3
		}.merge(@ctrl.graph.conf.xlabel ? {:forcelabels => true, :ranksep => 0.85} : {})
		@viz_graph = DotGraph.new(:G, graph_options)
		@token_graph = @viz_graph.subgraph(:rank => :same)
		@layer_graphs = {}
		@ctrl.graph.conf.combinations.each do |c|
			@layer_graphs[c] = c.weight < 0 ? @viz_graph.subgraph(:rank => :same) : @viz_graph.subgraph
		end
		@ctrl.graph.conf.layers.each do |l|
			@layer_graphs[l] = l.weight < 0 ? @viz_graph.subgraph(:rank => :same) : @viz_graph.subgraph
		end
		# speaker subgraphs
		if (speakers = @ctrl.graph.speaker_nodes.select{|sp| @tokens.map(&:speaker).include?(sp)}) != []
			@speaker_graphs = Hash[speakers.map{|s| [s, @viz_graph.subgraph(:rank => :same)]}]
			# induce speaker labels and layering of speaker graphs:
			gv_speaker_nodes = []
			@speaker_graphs.each do |speaker_node, speaker_graph|
				gv_speaker_nodes << speaker_graph.add_nodes(
					's' + speaker_node.id.to_s,
					{:shape => :plaintext, :label => speaker_node['name'], :fontname => @ctrl.graph.conf.font}
				)
				@viz_graph.add_edges(gv_speaker_nodes[-2], gv_speaker_nodes[-1], {:style => :invis}) if gv_speaker_nodes.length > 1
			end
			@timeline_graph = @viz_graph.subgraph(:rank => :same)
			@gv_anchor = @timeline_graph.add_nodes('anchor', {:style => :invis})
			@viz_graph.add_edges(gv_speaker_nodes[-1], @gv_anchor, {:style => :invis})
		end
	end

	def create_tokens
		@tokens.each_with_index do |token, i|
			options = {
				:fontname => @ctrl.graph.conf.font,
				:label => HTMLEntities.new.encode(build_label(token, @show_refs ? i : nil), :hexadecimal),
				:shape => :box,
				:style => :bold,
				:color => @ctrl.graph.conf.token_color,
				:fontcolor => @ctrl.graph.conf.token_color
			}
			if @ctrl.search_result.nodes[token.id]
				options[:color] = @ctrl.graph.conf.found_color
				@section_info[:textline] += '<span class="found_word">' + token.token + '</span> '
			elsif @filter[:mode] == 'hide' and @filter[:show] != token.fulfil?(@filter[:cond])
				options[:color] = @ctrl.graph.conf.filtered_color
				options[:fontcolor]= @ctrl.graph.conf.filtered_color
				@section_info[:textline] += '<span class="hidden_word">' + token.token + '</span> '
			else
				@section_info[:textline] += token.token + ' '
			end
			unless token.speaker
				@token_graph.add_nodes(token, options)
			else
				# create token and point on timeline:
				gv_token = @speaker_graphs[token.speaker].add_nodes(token, options)
				gv_time  = @timeline_graph.add_nodes('t' + token.id.to_s, {:shape => 'plaintext', :label => "#{token.start}\n#{token.end}", :fontname => @ctrl.graph.conf.font})
				# add ordering edge from speaker to speaker's first token
				@viz_graph.add_edges('s' + token.speaker.id.to_s, gv_token, {:style => :invis}) if i == 0
				# multiple lines between token and point on timeline in order to force correct order:
				@viz_graph.add_edges(gv_token, gv_time, {:weight => 9999, :style => :invis})
				@viz_graph.add_edges(gv_token, gv_time, {:arrowhead => :none, :weight => 9999})
				@viz_graph.add_edges(gv_token, gv_time, {:weight => 9999, :style => :invis})
				# order points on timeline:
				if i > 0
					@viz_graph.add_edges('t' + @tokens[i-1].id.to_s, gv_time, {:arrowhead => :none})
				else
					@viz_graph.add_edges(@gv_anchor, gv_time, {:style => :invis})
				end
			end
		end
	end

	def create_nodes
		@nodes.each_with_index do |node, i|
			options = {
				:fontname => @ctrl.graph.conf.font,
				:color => @ctrl.graph.conf.default_color,
				:shape => :box,
				:label => HTMLEntities.new.encode(build_label(node, @show_refs ? i : nil), :hexadecimal),
			}
			actual_layer_graph = nil
			if @filter[:mode] == 'hide' and @filter[:show] != node.fulfil?(@filter[:cond])
				options[:color] = @ctrl.graph.conf.filtered_color
			else
				if l = node.layer_or_combination
					options[:color] = l.color
					actual_layer_graph = @layer_graphs[l]
				end
			end
			options[:fontcolor] = options[:color]
			if @ctrl.search_result.nodes[node.id]
				options[:color] = @ctrl.graph.conf.found_color
				options[:penwidth] = 2
			end
			options[:style] = 'dashed' if !node.sentence
			@viz_graph.add_nodes(node, options)
			actual_layer_graph.add_nodes(node) if actual_layer_graph
		end
	end

	def create_edges
		@edges.each_with_index do |edge, i|
			label = HTMLEntities.new.encode(build_label(edge, @show_refs ? i : nil), :hexadecimal)
			options = {
				:fontname => @ctrl.graph.conf.font,
				:color => @ctrl.graph.conf.default_color,
				:weight => @ctrl.graph.conf.edge_weight,
				:constraint => true
			}.merge(
				@ctrl.graph.conf.xlabel ? {:xlabel => label} : {:label => label}
			)
			if @filter[:mode] == 'hide' and @filter[:show] != edge.fulfil?(@filter[:cond])
				options[:color] = @ctrl.graph.conf.filtered_color
			else
				if l = edge.layer_or_combination
					options[:color] = l.color
					if l.weight == 0
						options[:constraint] = false
					else
						options[:weight] = l.weight
						options[:constraint] = true
					end
				end
			end
			options[:fontcolor] = options[:color]
			if @ctrl.search_result.edges[edge.id]
				options[:color] = @ctrl.graph.conf.found_color
				options[:penwidth] = 2
			end
			@viz_graph.add_edges(edge.start, edge.end, options)
		end

		@order_edges.each do |edge|
			@viz_graph.add_edges(edge.start, edge.end, :style => :invis, :weight => 100)
		end
	end

	def build_label(e, i = nil)
		label = ''
		display_attr = e.attr.output
		if e.is_a?(Node)
			if e.type == 's' || e.type == 'p'
				label += display_attr.map{|key, value| "#{key}: #{value}<br/>"}.join
			elsif e.type == 't'
				display_attr.each do |key, value|
					case key
					when 'token'
						label = "#{value}\n#{label}"
					else
						label += "#{key}: #{value}\n"
					end
				end
				label += "t#{i}" if i
			else # normaler Knoten
				display_attr.each do |key,value|
					case key
					when 'cat'
						label = "#{value}\n#{label}"
					else
						label += "#{key}: #{value}\n"
					end
				end
				label += "n#{i}" if i
			end
		elsif e.is_a?(Edge)
			display_attr.each do |key,value|
				case key
				when 'cat'
					label = "#{value}\n#{label}"
				else
					label += "#{key}: #{value}\n"
				end
			end
			label += "e#{i}" if i
		end
		return label
	end
end
