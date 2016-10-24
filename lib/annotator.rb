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
