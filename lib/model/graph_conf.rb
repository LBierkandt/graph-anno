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

class GraphConf
	attr_accessor :font, :default_color, :token_color, :found_color, :filtered_color, :edge_weight, :xlabel, :layers, :combinations

	def initialize(h = {})
		h ||= {}
		@default = File::open('conf/display.yml'){|f| YAML::load(f)}
		@default.merge!(File::open('conf/layers.yml'){|f| YAML::load(f)})
		update(h)
	end

	def update(h = {})
		@font = h['font'] || @default['font']
		@default_color = h['default_color'] || @default['default_color']
		@token_color = h['token_color'] || @default['token_color']
		@found_color = h['found_color'] || @default['found_color']
		@filtered_color = h['filtered_color'] || @default['filtered_color']
		@edge_weight = h['edge_weight'] ? h['edge_weight'].to_i : @default['edge_weight']
		@xlabel = h['xlabel'] || @default['xlabel']
		@layers ||= []
		@combinations ||= []

		layer_hashes = h['layers'] || @default['layers']
		@layers = layer_hashes.map do |layer_hash|
			if layer = layer_by_shortcut[layer_hash['shortcut']]
				layer.update(layer_hash)
			else
				AnnoLayer.new(layer_hash.merge(:conf => self))
			end
		end
		combination_hashes = h['combinations'] || @default['combinations']
		@combinations = combination_hashes.map do |combination_hash|
			if combination = layer_by_shortcut[combination_hash['shortcut']]
				combination.update(combination_hash)
			else
				AnnoLayer.new(combination_hash.merge(:conf => self))
			end
		end
	end

	def clone
		new_conf = super
		new_conf.layers = @layers.map(&:clone)
		new_conf.combinations = @combinations.map(&:clone)
		return new_conf
	end

	def merge!(other)
		other.layers.each do |layer|
			unless @layers.map(&:shortcut).include?(layer.shortcut)
				@layers << layer
			end
		end
		other.combinations.each do |combination|
			unless @combinations.map{|c| c.layers.sort}.include?(combination.layers.sort)
				@combinations << combination
			end
		end
	end

	def to_h
		{
			:font => @font,
			:default_color => @default_color,
			:token_color => @token_color,
			:found_color => @found_color,
			:filtered_color => @filtered_color,
			:edge_weight => @edge_weight,
			:xlabel => @xlabel,
			:layers => @layers.map(&:to_h),
			:combinations => @combinations.map(&:to_h)
		}
	end

	def layers_and_combinations
		@layers + @combinations
	end

	def layer_by_shortcut
		Hash[layers_and_combinations.map{|l| [l.shortcut, l]}]
	end

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		self.to_h.to_json(*a)
	end
end

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
