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

class AnnoLayer
	attr_accessor :name, :shortcut, :layers, :color, :weight

	def initialize(h = {})
		@conf = h[:conf]
		update(h)
	end

	def update(h = {})
		@name = h['name'] || ''
		@shortcut = h['shortcut'] || ''
		@layers = h['layers'] ? h['layers'].map{|shortcut| @conf.layer_by_shortcut[shortcut]} : [self]
		@attr = h['attr'] # keep in the json in order to stay able to update format of part files
		@color = h['color'] || '#000000'
		@weight = h['weight'] ? h['weight'].to_i : 1
		self
	end

	def to_h
		{
			:name => @name,
			:shortcut => @shortcut,
			:layers => @layers == [self] ? nil : @layers.map(&:shortcut),
			:attr => @attr, # keep in the json in order to stay able to update format of part files
			:color => @color,
			:weight => @weight
		}.compact
	end

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		@shortcut.to_json(*a)
	end
end
