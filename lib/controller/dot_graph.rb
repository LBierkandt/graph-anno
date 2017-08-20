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

class DotGraph
	DotNode = Struct.new(:id, :options)
	DotEdge = Struct.new(:start, :end, :options)

	def initialize(name, options = {})
		@name = name
		@options = options
		@nodes = []
		@edges = []
		@subgraphs = []
	end

	def add_nodes(source, options = {})
		@nodes << DotNode.new(get_id(source), options)
		@nodes.last
	end

	def add_edges(start, target, options = {})
		@edges << DotEdge.new(get_id(start), get_id(target), options)
		@edges.last
	end

	def subgraph(options = {})
		@subgraphs << DotGraph.new(('a'..'z').to_a.shuffle[0..15].join, options)
		@subgraphs.last
	end

	def to_s(type = 'digraph')
		return '' if type == 'subgraph' && (@nodes + @edges).empty?
		"#{type} #{@name}{" +
			options_string(@options, ';') +
			@nodes.map{|n| "#{n.id}[#{options_string(n.options)}]"}.join +
			@edges.map{|e| "#{e.start}->#{e.end}[#{options_string(e.options)}]"}.join +
			@subgraphs.map{|sg| sg.to_s('subgraph')}.join +
			'}'
	end

	private

	def options_string(h, sep = ',')
		h.map do |k, v|
			if k == :label
				"#{k}=<#{v}>#{sep}"
			else
				"#{k}=\"#{v}\"#{sep}"
			end
		end.join
	end

	def get_id(source)
		source.respond_to?(:id) ? source.id.to_s : source.to_s
	end
end
