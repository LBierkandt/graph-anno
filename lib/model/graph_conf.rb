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
			unless @combinations.map{|c| c.layers.map(&:shortcut)}.include?(combination.layers.map(&:shortcut))
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

	def expand_shortcut(shortcut)
		if layer = layer_by_shortcut[shortcut]
			layer.layers.map(&:shortcut)
		else
			[]
		end
	end

	# returns the layer or layer combination that should be used for the display of the given layers list
	# @return [AnnoLayer]
	def display_layer(layer_list)
		layers_and_combinations.sort{|a, b| b.layers.length <=> a.layers.length}.each do |l|
			return l if layer_list and l.layers - layer_list == []
		end
		return nil
	end

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		self.to_h.to_json(*a)
	end
end
