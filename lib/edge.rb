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
		@layers = h[:layers].is_a?(AnnoLayer) ? h[:layers].layers : h[:layers] || []
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
	def delete(h = {})
		if h[:log]
			h[:log].add_change(:action => :delete, :element => self)
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
			:layers => @layers.empty? ? nil : @layers,
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
