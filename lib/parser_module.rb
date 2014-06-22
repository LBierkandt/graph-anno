# encoding: utf-8

# Copyright © 2014 Lennart Bierkandt <post@lennartbierkandt.de>
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

	def initialize
		super
		@makros = []
		if File.exists?('conf/search_makros.txt')
			File.open('conf/search_makros.txt', 'r:utf-8') do |datei|
				@makros = parse_query(datei.read)['def']
			end
		end
	end

	def parse_query(string, makros = @makros)
		ops = {
			'col'=>[],
			'cond'=>[],
			'def'=>makros,
			'edge'=>[],
			'link'=>[],
			'meta'=>[],
			'node'=>[],
			'nodes'=>[],
			'sort'=>[],
			'text'=>[]
		}
		lines = string.split("\n")
		
		puts 'Parsing input:'
		lines.each{|z| puts '  ' + z}
		puts
		
		lines.each do |line|
			begin
				if op = parse_line(line, ops['def'])
					ops[op[:operator]] << op
				end
			rescue StandardError => e
				raise e.message + " in line:\n" + line
			end
		end
		
		return ops
	end

	def parse_line(obj)
		if obj.class == String
			p = obj.strip.partition('#')[0].split(/\s/)
			if ['cond', 'sort'].include?(p[0])
				return {:operator => p[0]}.merge(parse_eval((p[1..-1] * ' ')))
			elsif p[0] == 'col'
				return {:operator => p[0], :title => p[1]}.merge(parse_eval((p[2..-1] * ' ')))
			else
				return parse_line(obj.lex_ql)
			end
		else
			if obj.length == 0 then return nil end
			arr = obj.clone
			operators = [
				'node',
				'nodes',
				'edge',
				'link',
				'text',
				'meta',
				'cond',
				'def',
				'sort', 
				'col'
			]
			if arr[0] and arr[0][:cl] == :bstring and operators.include?(arr[0][:str])
				op = {:operator => arr.shift[:str]}
				# Leerzeichen am Anfang entfernen:
				while true
					if arr[0] and arr[0][:cl] == :operator and arr[0][:str] == ' '
						arr.shift
					else break
					end
				end
			else #Fehler!
				raise "Undefined command \"#{arr[0][:str]}\""
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
					if ids.length == 0
					elsif ids.length == 1
						op[:id] = ids[0]
					elsif ids.length == 2
						op[:start], op[:end] = ids
					elsif ids.length == 3
						op[:id], op[:start], op[:end] = ids
					else #Fehler!
						raise 'Too many IDs in edge clause (max. three)'
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
					if ids.length == 2
						op[:start], op[:end] = ids
					else #Fehler!
						raise 'There must be two IDs in link clause'
					end
					p = parse_link(arr)
					op[:arg] = p[:op]
					op[:ids] = p[:ids]
				when 'meta'
					op[:cond] = parse_attributes(arr)[:op]
				when 'def'
					if [:bstring, :qstring].include?(arr[0][:cl])
						op[:name] = arr.shift[:str]
						op[:arg] = arr
					else # Fehler
						raise "def clause needs a name"
					end
			end
			return op
		end
	end

	def parse_attributes(obj)
		if obj.class == String
			return parse_attributes(obj.lex_ql)
		else
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
						if ['in', 'out', 'start', 'end', 'link', 'quant'].include?(p[:op][:operator])
							terms << p[:op]
						elsif @makros.map{|m| m[:name]}.include?(tok[:str])
							m = parse_attributes(@makros.select{|m| m[:name] == tok[:str]}[-1][:arg])
							terms << m[:op]
						else #Fehler!
							raise "Undefined string \"#{tok[:str]}\""
						end
						i += p[:length] - 1
					when :operator
						if ['!', '&', '|'].include?(tok[:str])
							terms << {'!'=>'not', '&'=>'and', '|'=>'or'}[tok[:str]]
						elsif tok[:str] == '('
							p = parse_attributes(obj[i+1..-1])
							terms << p[:op]
							i += p[:length]
						elsif tok[:str] == ')'
							i += 1
							break
						end
				end
				i += 1
			end
			# 'in', 'out' und 'link' ggf. in Quantor {1,1} einbetten
			terms.each_with_index do |t, i|
				if t.class == Hash && (['in', 'out', 'link'].include?(t[:operator]))
					terms[i] = {:operator => 'quant', :arg => t, :min => 1, :max => -1}
				end
			end
			return {:op => parse_term_sequence(terms), :length => i}
		end
	end

	def parse_attribute(obj)
		if obj.class == String
			return parse_attribute(obj.lex_ql)
		else
			key = obj[0][:str]
			i = 0
			op = {:operator => 'attr', :key => key}
			values = []
			value_expected = true
			while tok = obj[i]
				case tok[:cl]
					when :bstring, :qstring, :regex
						if value_expected
							values << {
								:value => tok[:str],
								:method => {:bstring=>'insens', :qstring=>'plain', :regex=>'regex'}[tok[:cl]]
							}
							value_expected = false
						else # Fehler
							raise "Wrong syntax in declaration of multiple possibilities for attribute value"
						end
					when :operator
						if value_expected
							values << {:value => '', :method => 'plain'} # oder sollte hier ":value=>nil"? Dann müßte aber fulfil anders definiert sein!
							value_expected = false
							break
						else
							if tok[:str] == '|'
								value_expected = true
							else
								value_expected = false
								break
							end
						end
				end
				i += 1
			end
			if value_expected then values << {:value => '', :method => 'plain'} end
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
	end

	def parse_element(obj)
		op = {:operator => obj[0][:str]}
		length = 1
		if obj[1] and obj[1][:cl] == :operator && obj[1][:str] == '('
			if op[:operator] == 'link'
				p = obj[2..-1].parse_link
				op[:arg] = p[:op]
			else
				p = obj[2..-1].parse_attributes
				op[:cond] = p[:op]
			end
			length += p[:length] + 1
		end
		if ['in', 'out', 'link'].include?(op[:operator]) and obj[length] and obj[length][:cl] == :quantor
			op = obj[length][:str].parse_quantor(op)
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
		if obj.class == String
			return parse_link(obj.lex_ql)
		else
			op = {}
			terms = []
			ids = []
			i = 0
			while tok = obj[i]
				case tok[:cl]
					when :bstring, :qstring
						if terms[-1].class == Hash then terms << 'seq' end
						p = parse_element(obj[i..-1])
						if ['node', 'edge', 'redge'].include?(p[:op][:operator])
							terms << p[:op]
							if p[:op][:id] then ids << p[:op][:id] end
						elsif @makros.map{|m| m[:name]}.include?(tok[:str])
							m = parse_link(@makros.select{|m| m[:name] == tok[:str]}[-1][:arg])
							terms << m[:op]
							if m[:op][:id] then ids << m[:op][:id] end
						end
						i += p[:length] - 1
					when :quantor
						terms[-1] = parse_quantor(tok[:str], terms[-1])
					when :operator
						if tok[:str] == '|'
							terms << 'or'
						elsif tok[:str] == '('
							if terms[-1].class == Hash then terms << 'seq' end
							p = parse_link(obj[i+1..-1])
							terms << p[:op]
							i += p[:length]
						elsif tok[:str] == ')'
							i += 1
							break
						end
				end
				i += 1
			end
			return {:op => parse_term_sequence(terms), :length => i, :ids => ids}
		end
	end

	def parse_text_search(obj)
		if obj.class == String
			return parse_text_search(obj.lex_ql)
		else
			op = {}
			terms = []
			ids = []
			i = 0
			while tok = obj[i]
				case tok[:cl]
					when :bstring, :qstring, :regex
						if terms[-1].class == Hash then terms << 'seq' end
						p = parse_word(obj[i..-1])
						terms << p[:op]
						i += p[:length] - 1
					when :quantor
						terms[-1] = parse_quantor(tok[:str], terms[-1])
					when :id
						terms[-1][:id] = tok[:str]
						ids << tok[:str]
					when :operator
						if tok[:str] == '|'
							terms << 'or'
						elsif tok[:str] == '('
							if terms[-1].class == Hash then terms << 'seq' end
							p = parse_text_search(obj[i+1..-1])
							terms << p[:op]
							ids += p[:ids]
							i += p[:length]
						elsif tok[:str] == ')'
							i += 1
							break
						end
					when :boundary
						if terms[-1].class == Hash then terms << 'seq' end
						terms << {:operator => 'boundary', :level => tok[:str]}
				end
				i += 1
			end
			return {:op => parse_term_sequence(terms), :length => i, :ids => ids}
		end
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
		if terms.length > 1
			raise "Attributes not linked by operator"
		end
		return terms[0]
	end

	def parse_eval(string)
		rueck = {:ids => {}, :string => string}
		string.scan(/@[_[:alnum:]]+/) do |id|
			rueck[:ids][$`.length..$`.length+$&.length-1] = id
		end
		return rueck
	end

	def parse_quantor(string, argument)
		op = {:operator => 'quant', :arg => argument}
		case string[0]
		when '{'
			m = string.match(/{\s*(-?\d*)\s*(,\s*(-?\d*)\s*)?}/)
			op[:min] = [0, m[1].to_i].max
			if m[2]
				op[:max] = if m[3] == '' then -1 else m[3].to_i end
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

class Graph
	include(Parser)
end
