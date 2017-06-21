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

class SearchResult
	attr_reader :valid, :tg, :nodes, :edges, :text
	alias_method :valid?, :valid

	def initialize
		reset
	end

	def reset
		@valid = false
		@tg = []
		@nodes = {}
		@edges = {}
		@text = ''
	end

	def set(results)
		@valid = true
		@tg = results
		@nodes = Hash[@tg.map(&:nodes).flatten.uniq.map{|n| [n.id, n]}]
		@edges = Hash[@tg.map(&:edges).flatten.uniq.map{|e| [e.id, e]}]
		@text = "#{@tg.length} matches"
	end

	def error(message)
		reset
		@text = message
	end

	def sections
		(@nodes.values + @edges.values.map{|e| e.end})
			.uniq.compact.map(&:sentence).compact
			.map{|s| [s] + s.ancestor_sections}.flatten.uniq
	end
end
