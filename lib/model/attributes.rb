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
		@host = h[:host]
		attr = h[:attr].is_a?(Array) ? hashify(h[:attr]) : (h[:attr] || {})
		private_attr = h[:private_attr].is_a?(Array) ? hashify(h[:private_attr]) : (h[:private_attr] || {})
		if h[:raw]
			# set directly
			@attr = attr.clone
			@private_attr = Hash[private_attr.map{|k, v| [@host.graph.get_annotator(:id => k), v.clone] }]
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
				{'' => @attr[''].to_h.select{|k, v| neutral?(k)}}
			)
		else
			@attr
		end
	end

	# returns a hash like {key => {value => [layers], ...}, ...}
	def grouped_output
		result = Hash.new{|h, k| h[k] = Hash.new{|h, k| h[k] = []}}
		output.each do |layer, key_value_map|
			key_value_map.each do |key, value|
				result[key][value] << layer
				result[key][value].uniq!
			end
		end
		result
	end

	def [](layer_or_key, key = nil)
		layer, key = key ? [layer_or_key, key] : [nil, layer_or_key]
		if layer
			output[layer].to_h[key]
		else
			if value_layers_map = grouped_output[key]
				value_layers_map.find{|value, layers| host_layers?(layers)}.to_a.first
			end
		end
	end

	# setter for attributes, excepting either `attr[key] = value` or `attr[layer, key] = value`
	# where the former sets the annotation for all layers of the host element
	def []=(layer_or_key, key_or_value, value = nil)
		layer, key, value = if value
			[layer_or_key, key_or_value, value]
		else
			[nil, layer_or_key, key_or_value]
		end
		hash = if @host.graph.current_annotator && !neutral?(key)
			@private_attr[@host.graph.current_annotator] ||= {}
		else
			@attr
		end
		if layer
			raise 'Annotations are restricted to the layers of their host element' unless @host.layers.include?(layer)
			(hash[layer] ||= {})[key] = value
		elsif @host.layers.empty?
			(hash[''] ||= {})[key] = value
		else
			@host.layers.each{|layer| (hash[layer] ||= {})[key] = value}
		end
	end

	def merge(hash)
		output.merge(hash)
	end

	def annotate_with(annotations)
		hash = annotations.is_a?(Hash) ? annotations : hashify(annotations)
		if @host.graph.current_annotator
			@private_attr[@host.graph.current_annotator] ||= {}
			@attr.deep_merge!(hash.select{|k, v| neutral?(k)})
			@private_attr[@host.graph.current_annotator].deep_merge!(hash.reject{|k, v| neutral?(k)})
		else
			@attr.deep_merge!(hash)
		end
		self
	end

	def remove_empty!
		remove_empty_values(@attr)
		if @host.graph.current_annotator
			remove_empty_values(@private_attr[@host.graph.current_annotator])
		end
		self
	end

	def set_layers(layers)
		return self unless layers
		([@attr] + @private_attr.values).each do |attr|
			attr.keep_if{|layer, key_value_map| (layers + ['']).include?(layer)}
		end
		layers.each do |layer|
			@attr[layer] ||= {}
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

	def layers
		@attr.except('').keys
	end

	def to_h
		{
			:attr => compress(@attr, preserve_layers: true),
			:private_attr => compress(Hash[@private_attr.map {|annotator, attr| [annotator.id, compress(attr)] }]),
		}.compact
	end

	private

	def compress(attr, options = {})
		compressed = if options[:preserve_layers]
			attr.reject{|k, v| k == '' && v.to_h.empty?}
		else
			attr.reject{|k, v| v.to_h.empty?}
		end
		compressed.empty? ? nil : compressed
	end

	def remove_empty_values(attr)
		attr.each do |layer, key_value_map|
			key_value_map.keep_if{|key, value| value}
		end
	end

	def hashify(annotations)
		raw_hash = Hash.new{|h, k| h[k] = {}}
		annotations.each do |a|
			if a[:layer]
				@host.graph.conf.layer_by_shortcut[a[:layer]].layers.map(&:shortcut).each do |shortcut|
					raw_hash[shortcut][a[:key]] = a[:value]
				end
			else
				if @host.layers.empty?
					raw_hash[''][a[:key]] = a[:value]
				else
					@host.layers.each do |shortcut|
						raw_hash[shortcut][a[:key]] = a[:value]
					end
				end
			end
		end
		raw_hash
	end

	def host_layers?(layers)
		(@host.layers - layers).empty?
	end
end
