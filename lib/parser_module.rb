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

class Array
	def parse_line(makros = $makros)
		if self.length == 0 then return nil end
		arr = self.clone
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
				op[:cond] = arr.parse_attributes(makros)[:op]
			when 'text'
				if arr[0] and arr[0][:cl] == :id
					op[:id] = arr.shift[:str]
				end
				p = arr.parse_text_search(makros)
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
				op[:cond] = arr.parse_attributes(makros)[:op]
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
				p = arr.parse_link(makros)
				op[:arg] = p[:op]
				op[:ids] = p[:ids]
			when 'meta'
				op[:cond] = arr.parse_attributes(makros)[:op]
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

	def parse_attributes(makros = $makros)
		op = {}
		terms = []
		i = 0
		while tok = self[i]
			case tok[:cl]
				when :key
					p = self[i..-1].parse_attribute
					terms << p[:op]
					i += p[:length] - 1
				when :qstring
					raise "Undefined string \"#{tok[:str]}\""
				when :bstring
					p = self[i..-1].parse_element(makros)
					if ['in', 'out', 'start', 'end', 'link', 'quant'].include?(p[:op][:operator])
						terms << p[:op]
					elsif makros.map{|m| m[:name]}.include?(tok[:str])
						m = makros.select{|m| m[:name] == tok[:str]}[-1][:arg].parse_attributes
						terms << m[:op]
					else #Fehler!
						raise "Undefined string \"#{tok[:str]}\""
					end
					i += p[:length] - 1
				when :operator
					if ['!', '&', '|'].include?(tok[:str])
						terms << {'!'=>'not', '&'=>'and', '|'=>'or'}[tok[:str]]
					elsif tok[:str] == '('
						p = self[i+1..-1].parse_attributes(makros)
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
		return {:op => terms.parse_term_sequence, :length => i}
	end

	def parse_attribute
		key = self[0][:str]
		i = 0
		op = {:operator => 'attr', :key => key}
		values = []
		value_expected = true
		while tok = self[i]
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

	def parse_element(makros = $makros)
		op = {:operator => self[0][:str]}
		length = 1
		if self[1] and self[1][:cl] == :operator && self[1][:str] == '('
			if op[:operator] == 'link'
				p = self[2..-1].parse_link(makros)
				op[:arg] = p[:op]
			else
				p = self[2..-1].parse_attributes(makros)
				op[:cond] = p[:op]
			end
			length += p[:length] + 1
		end
		if ['in', 'out', 'link'].include?(op[:operator]) and self[length] and self[length][:cl] == :quantor
			op = self[length][:str].parse_quantor(op)
			length += 1
		end
		if self[length] and self[length][:cl] == :id
			op[:id] = self[length][:str]
			length += 1
		end
		return {:op => op, :length => length}
	end

	def parse_word(makros = $makros)
		op = {
			:operator => 'attr',
			:key => 'token',
			:value => self[0][:str],
			:method => {:bstring=>'insens', :qstring=>'plain', :regex=>'regex'}[self[0][:cl]]
		}
		length = 1
		if self[1] and self[1][:cl] == :operator and self[1][:str] == '('
			p = self[2..-1].parse_attributes(makros)
			op = {:operator => 'and', :arg => [op, p[:op]]}
			length += p[:length] + 1
		end
		op = {:operator => 'node', :cond => op}
		return {:op => op, :length => length}
	end

	def parse_link(makros = $makros)
		op = {}
		terms = []
		ids = []
		i = 0
		while tok = self[i]
			case tok[:cl]
				when :bstring, :qstring
					if terms[-1].class == Hash then terms << 'seq' end
					p = self[i..-1].parse_element(makros)
					if ['node', 'edge', 'redge'].include?(p[:op][:operator])
						terms << p[:op]
						if p[:op][:id] then ids << p[:op][:id] end
					elsif makros.map{|m| m[:name]}.include?(tok[:str])
						m = makros.select{|m| m[:name] == tok[:str]}[-1][:arg].parse_link
						terms << m[:op]
						if m[:op][:id] then ids << m[:op][:id] end
					end
					i += p[:length] - 1
				when :quantor
					terms[-1] = tok[:str].parse_quantor(terms[-1])
				when :operator
					if tok[:str] == '|'
						terms << 'or'
					elsif tok[:str] == '('
						if terms[-1].class == Hash then terms << 'seq' end
						p = self[i+1..-1].parse_link(makros)
						terms << p[:op]
						i += p[:length]
					elsif tok[:str] == ')'
						i += 1
						break
					end
			end
			i += 1
		end
		return {:op => terms.parse_term_sequence, :length => i, :ids => ids}
	end

	def parse_text_search(makros = $makros)
		op = {}
		terms = []
		ids = []
		i = 0
		while tok = self[i]
			case tok[:cl]
				when :bstring, :qstring, :regex
					if terms[-1].class == Hash then terms << 'seq' end
					p = self[i..-1].parse_word(makros)
					terms << p[:op]
					i += p[:length] - 1
				when :quantor
					terms[-1] = tok[:str].parse_quantor(terms[-1])
				when :id
					terms[-1][:id] = tok[:str]
					ids << tok[:str]
				when :operator
					if tok[:str] == '|'
						terms << 'or'
					elsif tok[:str] == '('
						if terms[-1].class == Hash then terms << 'seq' end
						p = self[i+1..-1].parse_text_search(makros)
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
		return {:op => terms.parse_term_sequence, :length => i, :ids => ids}
	end

	def parse_term_sequence
		terms = self.map{|e| e.clone}
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
end

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
	
	def parse_query
		ops = {
			'col'=>[],
			'cond'=>[],
			'def'=>$makros,
			'edge'=>[],
			'link'=>[],
			'meta'=>[],
			'node'=>[],
			'nodes'=>[],
			'sort'=>[],
			'text'=>[]
		}
		lines = self.split("\n")
		
		puts 'Parsing input:'
		lines.each{|z| puts '  ' + z}
		puts
		
		lines.each do |line|
			begin
				if op = line.parse_line(ops['def'])
					ops[op[:operator]] << op
				end
			rescue StandardError => e
				raise e.message + " in line:\n" + line
			end
		end
		
		return ops
	end

	def parse_eval
		rueck = {:ids => {}, :string => self}
		self.scan(/@[_[:alnum:]]+/) do |id|
			rueck[:ids][$`.length..$`.length+$&.length-1] = id
		end
		return rueck
	end

	def parse_line(makros = $makros)
		p = self.strip.partition('#')[0].split(/\s/)
		if ['cond', 'sort'].include?(p[0])
			return {:operator => p[0]}.merge((p[1..-1] * ' ').parse_eval)
		elsif p[0] == 'col'
			return {:operator => p[0], :title => p[1]}.merge((p[2..-1] * ' ').parse_eval)
		else
			return self.lex_ql.parse_line(makros)
		end
	end
	
	def parse_attributes(makros = $makros)
		return self.lex_ql.parse_attributes(makros)
	end
	
	def parse_attribute
		return self.lex_ql.parse_attribute
	end
	
	def parse_link(makros = $makros)
		return self.lex_ql.parse_link(makros)
	end

	def parse_text_search(makros = $makros)
		return self.lex_ql.parse_text_search(makros)
	end

	def parse_quantor(argument)
		op = {:operator => 'quant', :arg => argument}
		case self[0]
		when '{'
			m = self.match(/{\s*(-?\d*)\s*(,\s*(-?\d*)\s*)?}/)
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

$makros = []
if File.exists?('conf/search_makros.txt')
	File.open('conf/search_makros.txt', 'r:utf-8') do |datei|
		$makros = datei.read.parse_query['def']
	end
end











