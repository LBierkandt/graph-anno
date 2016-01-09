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

class Attributes
	def initialize(h)
		attr = h[:attr] || {}
		private_attr = h[:private_attr] || {}
		@host = h[:host]
		if h[:raw]
			# set directly
			@attr = attr.clone
			@private_attr = Hash[private_attr.map {|k, v| [@host.graph.get_annotator(:id => k), v] }]
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
			return @host.graph.conf.layers.map{|l| l.attr}.include?(key)
		when 't'
			return key == 'token'
		when 's'
			return key == 'name'
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

	def [](key)
		output[key]
	end

	def []=(key, value)
		if @host.graph.current_annotator
			if neutral?(key)
				@attr[key] = value
			else
				@private_attr[@host.graph.current_annotator] ||= {}
				@private_attr[@host.graph.current_annotator][key] = value
			end
		else
			@attr[key] = value
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

	def neutral
		@attr
	end

	def delete_private(annotator)
		@private_attr.delete(annotator)
	end

	def clone
		Attributes.new({:host => @host, :raw => true}.merge(self.to_h))
	end

	def to_h
		h = {}
		h.merge!(:attr => @attr.clone) unless @attr.empty?
		h.merge!(:private_attr => Hash[@private_attr.map {|annotator, attr| [annotator.id, attr.clone] }]) unless @private_attr.empty?
		h
	end
end
