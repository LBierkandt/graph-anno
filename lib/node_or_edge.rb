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

class NodeOrEdge
	attr_reader :graph
	attr_accessor :attr, :type

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		self.to_h.to_json(*a)
	end

	# alternative getter for @attr hash
	def [](key)
		@attr[key]
	end

	# alternative setter for @attr hash
	def []=(key, value)
		@attr[key] = value
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

	# annotate self with the given attributes
	# @param attributes [Hash] the attributes to be added to self's annotations
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def annotate(attributes, log_step = nil)
		log_step.add_change(:action => :update, :element => self, :attr => attributes) if log_step
		@attr.annotate_with(attributes).remove_empty!
	end

	# whether self fulfils a given condition; returns numeral values for some condition types
	# @param bedingung [Hash] a condition hash
	# @param inherited [Hash] whether the annotations of the ancestor sections (if self is a sentence or section node) should be considered as well; defaults to false
	# @return [Boolean, Integer] true if self matches the given condition; number of connections for condition types 'in', 'out' and 'link'
	def fulfil?(bedingung, inherited = false)
		bedingung = @graph.parse_attributes(bedingung)[:op] if bedingung.is_a?(String)
		return true unless bedingung
		satzzeichen = '.,;:?!"'
		case bedingung[:operator]
		when 'attr'
			knotenwert = inherited && is_a?(Node) ? inherited_attributes[bedingung[:key]] : @attr[bedingung[:key]]
			wert = bedingung[:value]
			return true unless knotenwert || wert
			return false unless knotenwert && wert
			case bedingung[:method]
			when 'plain'
				return true if knotenwert == wert
			when 'insens'
				if bedingung[:key] == 'token'
					return true if UnicodeUtils.downcase(knotenwert.xstrip(satzzeichen)) == UnicodeUtils.downcase(wert)
				else
					return true if UnicodeUtils.downcase(knotenwert) == UnicodeUtils.downcase(wert)
				end
			when 'regex'
				return true if knotenwert.match(wert)
			end
			return false
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
		else
			return true
		end
	end
end
