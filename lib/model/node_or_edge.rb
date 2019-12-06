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

class NodeOrEdge
	attr_reader :graph
	attr_accessor :attr, :type, :layers

	# common tasks for element initialization
	def initialize(h)
		@graph = h[:graph]
		@id = h[:id]
		@type = h[:type]
		@custom = h[:custom]
		set_layer(h[:layers])
		@attr = Attributes.new(h.merge(:host => self))
	end

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		self.to_h.to_json(*a)
	end

	# alternative getter for @attr
	def [](key, layer = nil)
		@attr[key, layer]
	end

	# alternative setter for @attr, excepting either `attr[key] = value` or `attr[key, layer] = value`
	def []=(key, layer_or_value, value = nil)
		if value
			@attr[key, layer_or_value] = value
		else
			@attr[key] = layer_or_value
		end
	end

	# @return [String] self's cat attribute
	def cat
		@attr['cat']
	end

	# @param arg [String] self's new cat attribute
	def cat=(arg)
		@attr['cat'] = arg
	end

	# accessor method for the public/neutral annotations of self
	def public_attr
		@attr.public
	end

	# accessor method for the private annotations of self
	def private_attr(annotator_name)
		annotator = @graph.get_annotator(:name => annotator_name)
		@attr.private[annotator] || {}
	end

	# annotate self with the given annotations after validating them
	# @param annotations [Array] the annotations as an Array of Hashes in the form {:layer => ..., :key => ..., :value => ...}
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def annotate(annotations, log_step = nil)
		annotations ||= []
		effective_annotations = @graph.allowed_annotations(annotations, self)
		log_step.add_change(:action => :update, :element => self, :attr => effective_annotations) if log_step
		@attr.annotate_with(effective_annotations).remove_empty!
	end

	# set self's layer array
	# @param attributes [AnnoLayer] the new layer or layer combination
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def set_layer(layer, log_step = nil)
		layers_array = case layer
		when AnnoLayer
			layer.layers
		when Array
			layer.map{|l| l.is_a?(AnnoLayer) ? l : @graph.conf.layer_by_shortcut[l]}
		else
			[]
		end
		log_step.add_change(:action => :update, :element => self, :layers => layers_array, :attr => {}) if log_step
		@layers = layers_array
		@attr.keep_layers(@layers) if @attr
	end

	# returns a label for display of element
	# @param filter [Hash] filter from GraphView
	# @param ref [String] optionally a label for referencing the element in commands
	def build_label(options = {})
		if is_a?(Node)
			if type == 's' || type == 'p'
				return element_label(options).join(options[:mode] == :list ?  '&ensp;' : '<br>')
			elsif type == 't'
				label = element_label(options.merge(:privileged => 'token'))
			else # normaler Knoten
				label = element_label(options.merge(:privileged => 'cat'))
			end
		elsif is_a?(Edge)
			label = element_label(options.merge(:privileged => 'cat'))
		end
		label << options[:ref] if options[:ref]
		return label.join(options[:mode] == :list ?  '&ensp;' : '<br/>')
	end

	# is element hidden given the filter?
	# @param filter_or_nil [Hash] filter from GraphView
	def hidden?(filter_or_nil)
		filter = filter_or_nil.to_h
		filter[:mode] == 'hide' && filter[:show] != fulfil?(filter[:cond])
	end

	# whether self fulfils a given condition; returns numeral values for some condition types
	# @param bedingung [Hash] a condition hash
	# @param inherited [Boolean] whether the annotations of the ancestor sections (if self is a sentence or section node) should be considered as well; defaults to false
	# @return [Boolean, Integer] true if self matches the given condition; number of connections for condition types 'in', 'out' and 'link'
	def fulfil?(bedingung, inherited = false)
		bedingung = @graph.parse_attributes(bedingung)[:op] if bedingung.is_a?(String)
		return true unless bedingung
		satzzeichen = '.,;:?!"'
		case bedingung[:operator]
		when 'attr'
			element_value = (inherited && is_a?(Node) ? inherited_attributes : @attr)[bedingung[:key], bedingung[:layer]]
			value = bedingung[:value]
			return true unless element_value || value
			return false unless element_value && value
			case bedingung[:method]
			when 'plain'
				return true if element_value == value
			when 'insens'
				if bedingung[:key] == 'token'
					return true if UnicodeUtils.downcase(element_value.xstrip(satzzeichen)) == UnicodeUtils.downcase(value)
				else
					return true if UnicodeUtils.downcase(element_value) == UnicodeUtils.downcase(value)
				end
			when 'regex'
				return true if element_value.match(value)
			end
			return false
		when 'layer'
			return bedingung[:layers] - @layers == []
		when 'not'
			return (not self.fulfil?(bedingung[:arg]))
		when 'and'
			return self.fulfil?(bedingung[:arg][0]) && self.fulfil?(bedingung[:arg][1])
		when 'or'
			return self.fulfil?(bedingung[:arg][0]) || self.fulfil?(bedingung[:arg][1])
		when 'quant' # nur von Belang für 'in', 'out' und 'link'
			anzahl = self.fulfil?(bedingung[:arg])
			if anzahl >= bedingung[:min] && (anzahl <= bedingung[:max] || bedingung[:max] < 0)
				return true
			else
				return false
			end
		when 'in'
			if self.is_a?(Node)
				return @in.select{|k| k.fulfil?(bedingung[:cond])}.length
			else
				return 1
			end
		when 'out'
			if self.is_a?(Node)
				return @out.select{|k| k.fulfil?(bedingung[:cond])}.length
			else
				return 1
			end
		when 'link'
			if self.is_a?(Node)
				return self.links(bedingung[:arg]).length
			else
				return 1
			end
		when 'token'
			if self.is_a?(Node)
				return @type == 't'
			else
				return false
			end
		when 'i'
			if self.is_a?(Node)
				return !sentence
			else
				return true
			end
		when 'start'
			if self.is_a?(Edge) && !@start.fulfil?(bedingung[:cond])
				return false
			else
				return true
			end
		when 'end'
			if self.is_a?(Edge) && !@end.fulfil?(bedingung[:cond])
				return false
			else
				return true
			end
		when 'node'
			return self.is_a?(Node)
		when 'edge'
			return self.is_a?(Edge)
		else
			return true
		end
	end

	private

	# helper for #build_label
	def element_label(options = {})
		label = []
		attr.grouped_output.each do |key, value_layer_map|
			case key
			when options[:privileged]
				label = map_layers(value_layer_map, options) + label
			else
				label += map_layers(value_layer_map, options.merge(:key => key))
			end
		end
		label
	end

	# helper for #element_label
	def map_layers(value_layer_map, options = {})
		value_layer_map.map do |value, layers|
			raw_label = options[:key] ? "#{options[:key]}: #{value}" : value
			label = @graph.html_encoder.encode(raw_label, :hexadecimal)
			label += ' ' * (raw_label.length / 4) if options[:mode] != :list # compensate for poor centering of html labels
			if l = @graph.conf.display_layer(layers)
				if options[:mode] == :list
					label = "<span style=\"color: #{hidden?(options[:filter]) ? @graph.conf.filtered_color : l.color}\">#{label}</span>"
				else
					label = "<font color=\"#{hidden?(options[:filter]) ? @graph.conf.filtered_color : l.color}\">#{label}</font>"
				end
			end
			label
		end
	end
end
