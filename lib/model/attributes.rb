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

class Attributes
	def initialize(h)
		attr = h[:attr] || {}
		private_attr = h[:private_attr] || {}
		@host = h[:host]
		if h[:raw]
			# set directly
			@attr = expand(attr.clone)
			@private_attr = Hash[private_attr.map {|k, v| [@host.graph.get_annotator(:id => k), expand(v)] }]
		else
			# set via key-distinguishing function
			@attr = {}
			@private_attr = {}
			self.annotate_with(attr)
		end
	end

	def neutral?(key)
		case @host.type
		when 'a'
			return false
		when 't'
			return key == 'token'
		when 's', 'p'
			return true
		end
	end

	def output
		if @host.graph.current_annotator
			(@private_attr[@host.graph.current_annotator] || {}).merge(
				@attr.select{|k, v| neutral?(k)}
			)
		else
			@attr
		end
	end

	# returns a hash like {key => {value => [layers], ...}, ...}
	def grouped_output
		output.map_hash do |key, layer_value_map|
			layer_value_map.group_by{|l, v| v}.map_hash{|k, v| v.map{|a| a.first}}
		end
	end

	def [](key, layer = nil)
		if layer
			output[key][layer]
		else
			if result_array = grouped_output[key].find{|value, layers| host_layers?(layers)}
				result_array.first
			else
				nil
			end
		end
	end

	# setter for attributes, excepting either `attr[key] = value` or `attr[key, layer] = value`
	# where the former sets the annotation for all layers of the host element
	def []=(key, layer_or_value, value_or_layer = nil)
		value, layer = if value_or_layer
			[value_or_layer, layer_or_value]
		else
			[layer_or_value, nil]
		end
		hash = if @host.graph.current_annotator && !neutral?(key)
			@private_attr[@host.graph.current_annotator] ||= {}
		else
			@attr
		end
		if layer
			raise 'Annotations are restricted to the layers of their host element' unless @host.layers.include?(layer)
			(hash[key] ||= {})[layer] = value
		else
			hash[key] = expand_value(value)
		end
	end

	def merge(hash)
		output.merge(hash)
	end

	def annotate_with(hash)
		if @host.graph.current_annotator
			@private_attr[@host.graph.current_annotator] ||= {}
			@attr.merge!(hash.select{|k, v| neutral?(k)})
			@private_attr[@host.graph.current_annotator].merge!(hash.reject{|k, v| neutral?(k)})
		else
			@attr.merge!(hash)
		end
		self
	end

	def remove_empty!
		if @host.graph.current_annotator
			@attr.keep_if{|k, v| v}
			@private_attr[@host.graph.current_annotator].keep_if{|k, v| v}
		else
			@attr.keep_if{|k, v| v}
		end
		self
	end

	def reject(&block)
		output.reject(&block)
	end

	def select(&block)
		output.select(&block)
	end

	def public
		@attr
	end

	def private
		@private_attr
	end

	def delete_private(annotator)
		@private_attr.delete(annotator)
	end

	def clone
		Attributes.new({:host => @host, :raw => true}.merge(self.to_h))
	end

	def full_merge(other)
		Attributes.new({:host => @host, :raw => true}.merge(self.to_h.deep_merge(other.to_h)))
	end

	def to_h
		h = {}
		h.merge!(:attr => compress(@attr)) unless @attr.empty?
		h.merge!(:private_attr => Hash[@private_attr.map {|annotator, attr| [annotator.id, compress(attr)] }]) unless @private_attr.empty?
		h
	end

	private

	def expand(h)
		h.map_hash do |k, v|
			case v
			when String
				expand_value(v)
			when Hash
				Hash[v.map{|k, v| [@host.graph.conf.layer_by_shortcut[k], v]}]
			end
		end
	end

	def compress(h)
		h.map_hash do |k, h|
			if h.values.uniq.length == 1 && host_layers?(h.keys)
				h.values.first
			else
				h
			end
		end
	end

	def expand_value(value)
		if @host.layers.empty?
			{nil => value}
		else
			Hash[@host.layers.map{|layer| [layer, value]}]
		end
	end

	def host_layers?(layers)
		(@host.layers - layers).empty?
	end
end
