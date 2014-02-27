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

class Graph_display
	require 'graphviz'
	require 'htmlentities'
	
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
		@conf = File::open('conf/display.yml'){|f| YAML::load(f)}
		@conf.merge!(File::open('conf/layers.yml'){|f| YAML::load(f)})
	end

	def layers
		@conf['layers']
	end

	def layers_combinations
		@conf['layers'].merge(@conf['combinations'])
	end

	def draw_graph(format, path)
		puts 'Generating graph ...'
	
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
		@meta = nodes.select{|n| n.cat == 'meta'}[0]
		@tokens = if tok = nodes.select{|n| n.token}[0] then tok.sentence_tokens else [] end
		@nodes = nodes.select{|n| !n.token && n.cat != 'meta'}
		@edges = (@tokens.map{|t| t.in + t.out} + @nodes.map{|n| n.in + n.out}).flatten.uniq.select{|e| e.type == 'g'}
		t_edges = @tokens.map{|t| t.in + t.out}.flatten.uniq.select{|e| e.type == 't'}
	
		if @filter[:mode] == 'filter'
			@nodes.select!{|n| @filter[:show] == n.fulfil?(@filter[:cond])}
			@edges.select!{|e| @filter[:show] == e.fulfil?(@filter[:cond])}
		end
		
		if @meta
			satzinfo[:meta] = build_label(@meta)
		end
	
		@tokens.each_with_index do |token, i|
			color = @conf['token_color']
			fontcolor = @conf['token_color']
			if @found && @found[:all_nodes].include?(token)
				color = @conf['found_color']
				satzinfo[:textline] += '<span class="found_word">' + token.token + '</span> '
			elsif @filter[:mode] == 'hide' and @filter[:show] != token.fulfil?(@filter[:cond])
				color = @conf['filtered_color']
				fontcolor = @conf['filtered_color']
				satzinfo[:textline] += '<span class="hidden_word">' + token.token + '</span> '
			else
				satzinfo[:textline] += token.token + ' '
			end
			token_graph.add_nodes(
				token.ID,
				:fontname => @conf['font'],
				:label => HTMLEntities.new.encode(build_label(token, @show_refs ? i : nil), :hexadecimal),
				:shape => 'box',
				:style => 'bold',
				:color => color,
				:fontcolor => fontcolor
			)
		end
	
		@nodes.each_with_index do |node, i|
			color = @conf['default_color']
			if @filter[:mode] == 'hide' and @filter[:show] != node.fulfil?(@filter[:cond])
				color = @conf['filtered_color']
			else
				@conf['layers'].values.each do |l|
					if node.attr[l['attr']] == 't' then color = l['color'] end
				end
				@conf['combinations'].values.sort{|a,b| a['attr'].length <=> b['attr'].length}.each do |c|
					if c['attr'].all?{|a| node.attr[a] == 't'}
						color = c['color']
					end
				end
			end
			fontcolor = color
			if @found && @found[:all_nodes].include?(node)
				color = @conf['found_color']
			end
			viz_graph.add_nodes(
				node.ID,
				:fontname => @conf['font'],
				:label => HTMLEntities.new.encode(build_label(node, @show_refs ? i : nil), :hexadecimal),
				:shape => 'box',
				:color => color,
				:fontcolor => fontcolor
			)
		end
	
		@edges.each_with_index do |edge, i|
			color = @conf['default_color']
			weight = @conf['edge_weight']
			if @filter[:mode] == 'hide' and @filter[:show] != edge.fulfil?(@filter[:cond])
				color = @conf['filtered_color']
			else
				@conf['layers'].values.each do |l|
					if edge.attr[l['attr']] == 't'
						color = l['color']
						weight = l['weight']
					end
				end
				@conf['combinations'].values.sort{|a,b| a['attr'].length <=> b['attr'].length}.each do |c|
					if c['attr'].all?{|a| edge.attr[a] == 't'}
						color = c['color']
						weight = c['weight']
					end
				end
			end
			fontcolor = color
			if @found && @found[:all_edges].include?(edge)
				color = @conf['found_color']
			end
			viz_graph.add_edges(
				edge.start.ID,
				edge.end.ID,
				:fontname => @conf['font'],
				:label => HTMLEntities.new.encode(build_label(edge, @show_refs ? i : nil),
				:hexadecimal),
				:color=> color,
				:fontcolor => fontcolor,
				:weight => weight
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
		display_attr = e.attr.reject{|k,v| (@conf['layers'].map{|n,l| l['attr']} + ['sentence']).include?(k)}
		if e.kind_of?(Node)
			if e.cat == 'meta'
				display_attr.each do |key,value|
					case key
						when 'cat'
							label += ''
						else
							label += "#{key}: #{value}<br/>"
					end
				end
			elsif e.token
				display_attr.sort.each do |key, value|
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
end
