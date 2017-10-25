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

class Tagset < Array
	def initialize(graph, a = [], h = {})
		errors = {}
		a.to_a.each_with_index do |rule_hash, i|
			begin
				self << TagsetRule.new(rule_hash, graph)
			rescue RuntimeError => e
				errors[i] = e.message
			end
		end
		unless errors.empty?
			raise errors.to_json if h[:error_format] == :json
			raise errors.values.join("\n")
		end
	end

	def allowed_annotations(annotations, element)
		return annotations if self.empty?
		applicable_rules = self.select{|rule| element.fulfil?(rule.parsed_context)}
		annotations.select do |annotation|
			annotation[:value].nil? or
				applicable_rules.any?{|rule| rule.allowes?(annotation)} or
				(element.is_a?(Node) && element.type == 't' && annotation[:key] == 'token')
		end
	end

	def to_a
		self.map(&:to_h)
	end

	def to_json(*a)
		self.to_a.to_json(*a)
	end

	def for_autocomplete(elements = nil)
		applicable_rules = if elements
			select{|rule| elements.all?{|el| el.fulfil?(rule.parsed_context)}}
		else
			self
		end
		applicable_rules.map{|rule| rule.for_autocomplete}.flatten
	end
end

class TagsetRule
	attr_accessor :key, :values, :context, :parsed_context, :layer

	def initialize(h, graph)
		errors = []
		@graph = graph
		@context = h['context'].to_s
		begin
			@parsed_context = @graph.parse_attributes(@context, true)[:op]
		rescue RuntimeError
			errors << "Invalid context: \"#{@context}\""
		end
		@key = h['key'].strip
		@layer = h['layer']
		layer = @layer.to_s.parse_parameters[:words].find{|w| @graph.conf.layer_by_shortcut[w]}
		@layer_shortcuts = layer ? @graph.conf.layer_by_shortcut[layer].layers.map(&:shortcut) : nil
		begin
			@values = @graph.lex_ql(h['values']).select{|tok| [:bstring, :qstring, :regex].include?(tok[:cl])}
		rescue RuntimeError
			errors << "Invalid values: \"#{h['values']}\""
		end
		raise errors.join(';') unless errors.empty?
	end

	def to_h
		{:key => @key, :values => values_string, :context => @context, :layer => @layer}
	end

	def for_autocomplete
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

	def allowes?(annotation)
		return true if @key.empty?
		return false unless @key == annotation[:key]
		return true if @values == []
		if annotation[:layer] && @layer_shortcuts &&
			 !(@graph.conf.expand_shortcut(annotation[:layer]) - @layer_shortcuts).empty?
			return false
		end
		@values.any? do |rule|
			case rule[:cl]
			when :bstring, :qstring
				annotation[:value] == rule[:str]
			when :regex
				annotation[:value].match('^' + rule[:str] + '$')
			end
		end
	end
end
