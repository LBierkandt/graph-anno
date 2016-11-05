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

class String
	def lex_ql
		str = self.strip
		rueck = []
		operators = ['&', '|', '!', '(', ')', ' ']
		control_characters = [
			' ', '(', ')', ':',
			'!', '&', '|',
			'"', '/',
			'?', '+', '*', '{', '}',
			'@', '#',
			'^'
		]
		r = {}
		r[:operator] = '(' + operators.map{|op| Regexp.escape(op)} * '|' + ')'
		r[:alnum] = '[_[:alnum:]]+'
		r[:bstring] = '[^' + control_characters * '' + ']+'
		r[:qstring] = '"([^"]*(\\\"[^"]*)*([^"\\\]|\\\"))?"'
		r[:regex] = '\/([^\/]*(\\\/[^\/]*)*([^\/\\\]|\\\/))?\/'
		r[:quantor] = '({\s*(-?\d*)\s*(,\s*(-?\d*)\s*)?}|\?|\+|\*)'
		r[:id] = '@' + r[:alnum]
		r[:variable] = ':' + r[:alnum]
		r[:boundary] = '\^' + r[:bstring]
		r[:string] = '(' + r[:bstring] + '|' + r[:qstring] + ')'
		r[:key] = r[:string] + ':'
		r.keys.each{|k| r[k] = Regexp.new('^' + r[k])}

		while str != ''
			m = nil
			if m = str.match(/^#/)
				break
			elsif m = str.match(r[:operator])
				rueck << {:cl => :operator, :str => m[0]}
			elsif m = str.match(r[:key])
				if m[2]
					rueck << {:cl => :key, :str => m[2]}
				else
					rueck << {:cl => :key, :str => m[1]}
				end
			elsif m = str.match(r[:bstring])
				rueck << {:cl => :bstring, :str => m[0]}
			elsif m = str.match(r[:qstring])
				rueck << {:cl => :qstring, :str => m[0][1..-2].gsub('\"', '"')}
			elsif m = str.match(r[:regex])
				rueck << {:cl => :regex, :str => m[0][1..-2]}
			elsif m = str.match(r[:quantor])
				rueck << {:cl => :quantor, :str => m[0]}
			elsif m = str.match(r[:id])
				raise 'ID assignment error' if rueck.last[:cl] == :boundary
				rueck << {:cl => :id, :str => m[0]}
			elsif m = str.match(r[:boundary])
				rueck << {:cl => :boundary, :str => m[0][1..-1]}
			elsif m = str.match(r[:variable])
				rueck << {:cl => :variable, :str => m[0]}
			else
				raise 'Syntax error'
			end

			if m
				str = str[m[0].length..-1]
			else
				break
			end
		end

		return rueck
	end
end

module Parser
	@@query_operators = [
		'node',
		'nodes',
		'edge',
		'link',
		'text',
		'meta',
		'cond',
		'def',
		'sort',
		'col',
	]
	@@annotation_commands = [
		'a',
		'n',
		'e',
		'p', 'g',
		'c', 'h',
		'd',
		'ni',
		'di', 'do',
		'tb', 'ta', 'ti',
		'l',
	]
	@@keywords = @@query_operators + @@annotation_commands

	def parse_query(string)
		ops = {:all => []}
		@@keywords.each{|c| ops[c] = []}
		ops['def'] = @makros

		string.split("\n").each do |line|
			begin
				if op = parse_line(line, ops['def'])
					ops[op[:operator]] << op
					ops[:all] << op
				end
			rescue StandardError => e
				raise e.message + " on line:\n" + line
			end
		end

		return ops
	end

	def parse_line(obj, makros)
		if obj.is_a?(String)
			p = obj.strip.split(/\s/)
			if ['cond', 'sort'].include?(p[0])
				return {:operator => p[0]}.merge(extract_ids((p[1..-1] * ' ')))
			elsif p[0] == 'col'
				return {:operator => p[0], :title => p[1]}.merge(extract_ids((p[2..-1] * ' ')))
			elsif @@annotation_commands.include?(p[0])
				return {:operator => p[0]}.merge(p[1..-1].join(' ').parse_parameters)
			else
				return parse_line(obj.lex_ql, makros)
			end
		else
			return nil if obj.length == 0
			arr = obj.clone
			raise "Undefined command \"#{arr[0][:str]}\"" unless arr[0][:cl] == :bstring and @@query_operators.include?(arr[0][:str])
			op = {:operator => arr.shift[:str]}
			# Leerzeichen am Anfang entfernen:
			loop do
				break unless arr[0] and arr[0][:cl] == :operator and arr[0][:str] == ' '
				arr.shift
			end
			case op[:operator]
			when 'node', 'nodes'
				if arr[0] and arr[0][:cl] == :id
					op[:id] = arr.shift[:str]
				end
				op[:cond] = parse_attributes(arr)[:op]
			when 'text'
				if arr[0] and arr[0][:cl] == :id
					op[:id] = arr.shift[:str]
				end
				p = parse_text_search(arr)
				op[:arg] = p[:op]
				op[:ids] = p[:ids]
			when 'edge'
				ids = []
				while arr[0]
					if arr[0][:cl] == :operator and arr[0][:str] == ' '
						arr.shift
					elsif arr[0][:cl] == :bstring and arr[0][:str] == '>'
						arr.shift
					elsif arr[0][:cl] == :id
						ids << arr.shift[:str]
					else break
					end
				end
				case ids.length
				when 0
				when 1
					op[:id] = ids[0]
				when 2
					op[:start], op[:end] = ids
				when 3
					op[:id], op[:start], op[:end] = ids
				else #Fehler!
					raise 'Too many ids in edge clause (max. three)'
				end
				op[:cond] = parse_attributes(arr)[:op]
			when 'link'
				ids = []
				while arr[0]
					if arr[0][:cl] == :operator and arr[0][:str] == ' '
						arr.shift
					elsif arr[0][:cl] == :bstring and arr[0][:str] == '>'
						arr.shift
					elsif arr[0][:cl] == :id
						ids << arr.shift[:str]
					else break
					end
				end
				raise 'There must be two ids in link clause' unless ids.length == 2
				op[:start], op[:end] = ids
				p = parse_link(arr)
				op[:arg] = p[:op]
				op[:ids] = p[:ids]
			when 'meta'
				op[:cond] = parse_attributes(arr)[:op]
			when 'def'
				raise "def clause needs a name" unless [:bstring, :qstring].include?(arr[0][:cl])
				op[:name] = arr.shift[:str]
				op[:arg] = arr
			end
			return op
		end
	end

	def parse_attributes(obj)
		return parse_attributes(obj.lex_ql) if obj.is_a?(String)
		op = {}
		terms = []
		i = 0
		while tok = obj[i]
			case tok[:cl]
			when :key
				p = parse_attribute(obj[i..-1])
				terms << p[:op]
				i += p[:length] - 1
			when :qstring
				raise "Undefined string \"#{tok[:str]}\""
			when :bstring
				p = parse_element(obj[i..-1])
				if ['in', 'out', 'start', 'end', 'link', 'quant', 'token'].include?(p[:op][:operator])
					terms << p[:op]
				elsif @makros.map{|m| m[:name]}.include?(tok[:str])
					m = parse_attributes(@makros.select{|m| m[:name] == tok[:str]}[-1][:arg])
					terms << m[:op]
				else #Fehler!
					raise "Undefined string \"#{tok[:str]}\""
				end
				i += p[:length] - 1
			when :operator
				case tok[:str]
				when '!', '&', '|'
					terms << {'!' => 'not', '&' => 'and', '|' => 'or'}[tok[:str]]
				when '('
					p = parse_attributes(obj[i+1..-1])
					terms << p[:op]
					i += p[:length]
				when ')'
					i += 1
					break
				end
			end
			i += 1
		end
		# 'in', 'out' und 'link' ggf. in Quantor {1,1} einbetten
		terms.each_with_index do |t, i|
			if t.is_a?(Hash) && (['in', 'out', 'link'].include?(t[:operator]))
				terms[i] = {:operator => 'quant', :arg => t, :min => 1, :max => -1}
			end
		end
		return {:op => parse_term_sequence(terms), :length => i}
	end

	def parse_attribute(obj)
		return parse_attribute(obj.lex_ql) if obj.is_a?(String)
		key = obj[0][:str]
		i = 0
		op = {:operator => 'attr', :key => key}
		values = []
		value_expected = true
		while tok = obj[i]
			case tok[:cl]
			when :bstring, :qstring, :regex
				raise "Wrong syntax in declaration of multiple possibilities for attribute value" unless value_expected
				values << {
					:value => tok[:str],
					:method => {:bstring=>'insens', :qstring=>'plain', :regex=>'regex'}[tok[:cl]]
				}
				value_expected = false
			when :operator
				values << {:value => nil, :method => 'plain'} if value_expected
				if tok[:str] == '|'
					value_expected = true
				else
					value_expected = false
					break
				end
			end
			i += 1
		end
		values << {:value => nil, :method => 'plain'} if value_expected
		# build operation
		op.merge!(values.pop)
		while values.length > 0
			old_op = op.clone
			op = {
				:operator => 'or',
				:arg => [
					{:operator => 'attr', :key => key}.merge(values.pop),
					old_op
				]
			}
		end
		return {:op => op, :length => i}
	end

	def parse_element(obj)
		op = {:operator => obj[0][:str]}
		length = 1
		if obj[1] and obj[1][:cl] == :operator && obj[1][:str] == '('
			if op[:operator] == 'link'
				p = parse_link(obj[2..-1])
				op[:arg] = p[:op]
			else
				p = parse_attributes(obj[2..-1])
				op[:cond] = p[:op]
			end
			length += p[:length] + 1
		end
		if ['in', 'out', 'link'].include?(op[:operator]) and obj[length] and obj[length][:cl] == :quantor
			op = parse_quantor(obj[length][:str], op)
			length += 1
		end
		if obj[length] and obj[length][:cl] == :id
			op[:id] = obj[length][:str]
			length += 1
		end
		return {:op => op, :length => length}
	end

	def parse_word(obj)
		op = {
			:operator => 'attr',
			:key => 'token',
			:value => obj[0][:str],
			:method => {:bstring=>'insens', :qstring=>'plain', :regex=>'regex'}[obj[0][:cl]]
		}
		length = 1
		if obj[1] and obj[1][:cl] == :operator and obj[1][:str] == '('
			p = parse_attributes(obj[2..-1])
			op = {:operator => 'and', :arg => [op, p[:op]]}
			length += p[:length] + 1
		end
		op = {:operator => 'node', :cond => op}
		return {:op => op, :length => length}
	end

	def parse_link(obj)
		return parse_link(obj.lex_ql) if obj.is_a?(String)
		op = {}
		terms = []
		ids = []
		i = 0
		while tok = obj[i]
			case tok[:cl]
			when :bstring, :qstring
				terms << 'seq' if terms[-1].is_a?(Hash)
				p = parse_element(obj[i..-1])
				if ['node', 'edge', 'redge'].include?(p[:op][:operator])
					terms << p[:op]
					ids << p[:op][:id] if p[:op][:id]
				elsif @makros.map{|m| m[:name]}.include?(tok[:str])
					m = parse_link(@makros.select{|m| m[:name] == tok[:str]}[-1][:arg])
					terms << m[:op]
					ids << m[:op][:id] if m[:op][:id]
				end
				i += p[:length] - 1
			when :quantor
				terms[-1] = parse_quantor(tok[:str], terms[-1])
			when :operator
				case tok[:str]
				when '|'
					terms << 'or'
				when '('
					terms << 'seq' if terms[-1].is_a?(Hash)
					p = parse_link(obj[i+1..-1])
					terms << p[:op]
					i += p[:length]
				when ')'
					i += 1
					break
				end
			end
			i += 1
		end
		raise 'A link must consist of at least one edge' if terms.length == 0
		return {:op => parse_term_sequence(terms), :length => i, :ids => ids}
	end

	def parse_text_search(obj)
		return parse_text_search(obj.lex_ql) if obj.is_a?(String)
		op = {}
		terms = []
		ids = []
		i = 0
		while tok = obj[i]
			case tok[:cl]
			when :bstring, :qstring, :regex
				terms << 'seq' if terms[-1].is_a?(Hash)
				p = parse_word(obj[i..-1])
				terms << p[:op]
				i += p[:length] - 1
			when :quantor
				terms[-1] = parse_quantor(tok[:str], terms[-1])
			when :id
				terms[-1][:id] = tok[:str]
				ids << tok[:str]
			when :operator
				case tok[:str]
				when '|'
					terms << 'or'
				when '('
					terms << 'seq' if terms[-1].is_a?(Hash)
					p = parse_text_search(obj[i+1..-1])
					terms << p[:op]
					ids += p[:ids]
					i += p[:length]
				when ')'
					i += 1
					break
				end
			when :boundary
				terms << 'seq' if terms[-1].is_a?(Hash)
				terms << {:operator => 'boundary', :level => tok[:str]}
			end
			i += 1
		end
		return {:op => parse_term_sequence(terms), :length => i, :ids => ids}
	end

	def parse_term_sequence(obj)
		terms = obj.map{|e| e.clone}
		while i = terms.rindex('not')
			terms[i] = {:operator => 'not', :arg => terms.slice!(i+1)}
		end
		['seq', 'and', 'or'].each do |operator|
			while i = terms.rindex(operator)
				terms[i] = {:operator => operator, :arg => [terms[i-1], terms[i+1]]}
				terms.delete_at(i+1)
				terms.delete_at(i-1)
			end
		end
		raise "Attributes not linked by operator" if terms.length > 1
		return terms[0]
	end

	def extract_ids(string)
		{:ids => string.scan(/@[_[:alnum:]]+/), :string => string}
	end

	def parse_quantor(string, argument)
		op = {:operator => 'quant', :arg => argument}
		case string[0]
		when '{'
			m = string.match(/{\s*(-?\d*)\s*(,\s*(-?\d*)\s*)?}/)
			op[:min] = [0, m[1].to_i].max
			if m[2]
				op[:max] = m[3] == '' ? -1 : m[3].to_i
			else
				op[:max] = op[:min]
			end
		when '?'
			op[:min] = 0
			op[:max] = 1
		when '*'
			op[:min] = 0
			op[:max] = -1
		when '+'
			op[:min] = 1
			op[:max] = -1
		end
		return op
	end
end
