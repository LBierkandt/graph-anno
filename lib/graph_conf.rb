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

class GraphConf
	attr_accessor :font, :default_color, :token_color, :found_color, :filtered_color, :edge_weight, :xlabel, :layers, :combinations

	def initialize(h = {})
		h ||= {}
		default = File::open('conf/display.yml'){|f| YAML::load(f)}
		default.merge!(File::open('conf/layers.yml'){|f| YAML::load(f)})

		@font = h['font'] || default['font']
		@default_color = h['default_color'] || default['default_color']
		@token_color = h['token_color'] || default['token_color']
		@found_color = h['found_color'] || default['found_color']
		@filtered_color = h['filtered_color'] || default['filtered_color']
		@edge_weight = h['edge_weight'] || default['edge_weight']
		@xlabel = h['xlabel'] || default['xlabel']
		if h['layers']
			@layers = h['layers'].map{|l| AnnoLayer.new(l)}
		else
			@layers = default['layers'].map{|l| AnnoLayer.new(l)}
		end
		if h['combinations']
			@combinations = h['combinations'].map{|c| AnnoLayer.new(c)}
		else
			@combinations = default['combinations'].map{|c| AnnoLayer.new(c)}
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
			unless @layers.map(&:attr).include?(layer.attr)
				@layers << layer
			end
		end
		other.combinations.each do |combination|
			unless @combinations.map(&:attr).include?(combination.attr)
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

	def layer_shortcuts
		layers_and_combinations.map{|l| {l.shortcut => l.name}}.reduce{|m, h| m.merge(h)}
	end

	def layer_attributes
		h = {}
		layers_and_combinations.map do |l|
			h[l.name] = [*l.attr].map{|attr| {attr => 't'}}.reduce{|m, h| m.merge(h)}
		end
		return h
	end

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		self.to_h.to_json(*a)
	end
end

class AnnoLayer
	attr_accessor :name, :attr, :shortcut, :color, :weight

	def initialize(h = {})
		@name = h['name'] || ''
		@attr = h['attr'] || ''
		@shortcut = h['shortcut'] || ''
		@color = h['color'] || '#000000'
		@weight = h['weight'] || '1'
		@graph = h['graph'] || nil
	end

	def to_h
		{
			:name => @name,
			:attr => @attr,
			:shortcut => @shortcut,
			:color => @color,
			:weight => @weight
		}
	end
end
