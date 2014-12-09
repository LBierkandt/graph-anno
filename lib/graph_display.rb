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

require 'yaml'
require 'graphviz'
	require 'open3'
require 'htmlentities'

class GraphDisplay
	attr_reader :graph, :nodes, :edges, :meta, :tokens
	attr_accessor :sentence, :show_refs, :found, :filter

	def initialize(graph)
		@graph = graph
		@sentence = nil
		@meta = nil
		@tokens = []
		@nodes = []
		@edges = []
		@show_refs = true
		@found = nil
		@filter = {:mode => 'unfilter'}
	end

	def draw_graph(format, path)
		puts "Generating graph for sentence \"#{@sentence}\"..."

		viz_graph = GraphViz.new(
			:G,
			:type => 'digraph',
			:rankdir => 'TB',
			:use => 'dot',
			:ranksep => '.3'
		)
		token_graph = viz_graph.subgraph(:rank => 'same')

		satzinfo = {:textline => '', :meta => ''}

		nodes = @graph.nodes.values.select{|n| n.sentence == @sentence}
		@meta = nodes.select{|n| n.type == 's'}[0]
		@tokens = if tok = nodes.select{|n| n.type == 't'}[0] then tok.sentence_tokens else [] end
		@nodes = nodes.select{|n| n.type != 't' && n.type != 's'}
		@edges = (@tokens + @nodes).map{|t| t.in + t.out}.flatten.uniq.select{|e| e.type == 'a'}
		t_edges = @tokens.map{|t| t.in + t.out}.flatten.uniq.select{|e| e.type == 'o'}

		if @filter[:mode] == 'filter'
			@nodes.select!{|n| @filter[:show] == n.fulfil?(@filter[:cond])}
			@edges.select!{|e| @filter[:show] == e.fulfil?(@filter[:cond])}
		end

		if @meta
			satzinfo[:meta] = build_label(@meta)
		end

		@tokens.each_with_index do |token, i|
			color = @graph.conf.token_color
			fontcolor = @graph.conf.token_color
			if @found && @found[:all_nodes].include?(token)
				color = @graph.conf.found_color
				satzinfo[:textline] += '<span class="found_word">' + token.token + '</span> '
			elsif @filter[:mode] == 'hide' and @filter[:show] != token.fulfil?(@filter[:cond])
				color = @graph.conf.filtered_color
				fontcolor = @graph.conf.filtered_color
				satzinfo[:textline] += '<span class="hidden_word">' + token.token + '</span> '
			else
				satzinfo[:textline] += token.token + ' '
			end
			token_graph.add_nodes(
				token.ID,
				:fontname => @graph.conf.font,
				:label => HTMLEntities.new.encode(build_label(token, @show_refs ? i : nil), :hexadecimal),
				:shape => 'box',
				:style => 'bold',
				:color => color,
				:fontcolor => fontcolor
			)
		end

		@nodes.each_with_index do |node, i|
			color = @graph.conf.default_color
			if @filter[:mode] == 'hide' and @filter[:show] != node.fulfil?(@filter[:cond])
				color = @graph.conf.filtered_color
			else
				@graph.conf.layers.each do |l|
					if node[l.attr] == 't' then color = l.color end
				end
				@graph.conf.combinations.sort{|a,b| a.attr.length <=> b.attr.length}.each do |c|
					if c.attr.all?{|a| node[a] == 't'}
						color = c.color
					end
				end
			end
			fontcolor = color
			if @found && @found[:all_nodes].include?(node)
				color = @graph.conf.found_color
			end
			viz_graph.add_nodes(
				node.ID,
				:fontname => @graph.conf.font,
				:label => HTMLEntities.new.encode(build_label(node, @show_refs ? i : nil), :hexadecimal),
				:shape => 'box',
				:color => color,
				:fontcolor => fontcolor
			)
		end

		@edges.each_with_index do |edge, i|
			color = @graph.conf.default_color
			weight = @graph.conf.edge_weight
			constraint = true
			if @filter[:mode] == 'hide' and @filter[:show] != edge.fulfil?(@filter[:cond])
				color = @graph.conf.filtered_color
			else
				@graph.conf.layers.each do |l|
					if edge[l.attr] == 't'
						color = l.color
						weight = l.weight
						constraint = false if weight == 0
					end
				end
				@graph.conf.combinations.sort{|a,b| a.attr.length <=> b.attr.length}.each do |c|
					if c.attr.all?{|a| edge[a] == 't'}
						color = c.color
						weight = c.weight
					end
				end
			end
			fontcolor = color
			if @found && @found[:all_edges].include?(edge)
				color = @graph.conf.found_color
			end
			viz_graph.add_edges(
				edge.start.ID,
				edge.end.ID,
				:fontname => @graph.conf.font,
				:label => HTMLEntities.new.encode(build_label(edge, @show_refs ? i : nil),
				:hexadecimal),
				:color=> color,
				:fontcolor => fontcolor,
				:weight => weight,
				:constraint => constraint
			)
		end

		t_edges.each do |edge|
			#len => 0
			viz_graph.add_edges(edge.start.ID, edge.end.ID, :style => 'invis', :weight => 100)
		end

		viz_graph.output(format => '"'+path+'"')

		return satzinfo
	end

	def build_label(e, i = nil)
		label = ''
		display_attr = e.attr.reject{|k,v| (@graph.conf.layers.map{|l| l.attr}).include?(k)}
		if e.kind_of?(Node)
			if e.type == 's'
				display_attr.each do |key,value|
					label += "#{key}: #{value}<br/>"
				end
			elsif e.token
				display_attr.each do |key, value|
					case key
						when 'token'
							label = "#{value}\n#{label}"
						else
							label += "#{key}: #{value}\n"
					end
				end
				if i
					label += "t" + i.to_s
				end
			else # normaler Knoten
				display_attr.each do |key,value|
					case key
						when 'cat'
							label = "#{value}\n#{label}"
						else
							label += "#{key}: #{value}\n"
					end
				end
				if i
					label += "n" + i.to_s
				end
			end
		elsif e.kind_of?(Edge)
			display_attr.each do |key,value|
				case key
					when 'cat'
						label = "#{value}\n#{label}"
					else
						label += "#{key}: #{value}\n"
				end
			end
			if i
				label += "e" + i.to_s
			end
		end
		return label
	end

	def build_sentence_html(sentence_list)
		puts 'Generating formatted sentence list ...'
		sentence_string = ''
		if @found
			sentence_list.each do |n|
				if @found[:sentences].include?(n)
					sentence_string += '<option value="' + n + '" class="found_sentence">' + n + '</option>'
				else
					sentence_string += '<option value="' + n + '">' + n + '</option>'
				end
			end
		else
			sentence_list.each do |n|
				sentence_string += '<option value="' + n + '">' + n + '</option>'
			end
		end
		return sentence_string
	end

end
