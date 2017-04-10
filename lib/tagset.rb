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

class Tagset < Array
	attr_reader :for_autocomplete

	def initialize(graph, a = [])
		a.to_a.each do |rule_hash|
			self << TagsetRule.new(rule_hash, graph)
		end
		@for_autocomplete = to_autocomplete
	end

	def allowed_attributes(attr, element)
		return attr.clone if self.empty?
		applicable_rules = self.select{|rule| element.fulfil?(rule.parsed_context)}
		attr.select do |key, value|
			value.nil? or
				applicable_rules.any?{|rule| rule.allowes?(key, value)} or
				(element.is_a?(Node) && element.type == 't' && key == 'token')
		end
	end

	def to_a
		self.map(&:to_h)
	end

	def to_json(*a)
		self.to_a.to_json(*a)
	end

	private

	def to_autocomplete
		self.map{|rule| rule.to_autocomplete}.flatten
	end
end

class TagsetRule
	attr_accessor :key, :values, :context, :parsed_context

	def initialize(h, graph)
		@key = h['key'].strip
		@values = h['values'].lex_ql.select{|tok| [:bstring, :qstring, :regex].include?(tok[:cl])}
		@context = h['context'].to_s
		@parsed_context = graph.parse_attributes(@context)[:op]
	end

	def to_h
		{:key => @key, :values => values_string, :context => @context}
	end

	def to_autocomplete
		@values.map do |tok|
			if tok[:cl] == :bstring
				"#{@key}:#{tok[:str]}"
			elsif tok[:cl] == :qstring
				"#{@key}:\"#{tok[:str]}\""
			end
		end.compact
	end

	def values_string
		@values.map do |tok|
			case tok[:cl]
			when :bstring
				tok[:str]
			when :qstring
				'"' + tok[:str] + '"'
			when :regex
				'/' + tok[:str] + '/'
			end
		end * ' '
	end

	def allowes?(key, value)
		return true if @key.empty?
		return false unless @key == key
		return true if @values == []
		@values.any? do |rule|
			case rule[:cl]
			when :bstring, :qstring
				value == rule[:str]
			when :regex
				value.match('^' + rule[:str] + '$')
			end
		end
	end
end
