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

class Array
	def most_frequent
		group_by{|i| i}.values.max{|x, y| x.length <=> y.length}[0]
	end

	def text
		self.map(&:text) * ' '
	end

	def groups_linked?(links)
		return true if self.length <= 1
		self[1..-1].each_with_index do |g, i|
			if links.any?{|l| l & self[0] != [] and l & g != []}
				new = self.clone
				new[0] += new.delete_at(i)
				return new.groups_linked?(links)
				break
			end
		end
		return false
	end
end

class Hash
	# @param h2 [Hash] the hash to be tested for inclusion in self
	# @return [Boolean] true if the key-value pairs of h2 are a subset of self
	def includes(h2)
		if h2.to_h == {}
			return true
		else
			return h2.any?{|k,v| self[k] == v}
		end
	end

	# creates a new hash by applying the given block to every key-value pair of self and assigning the result as value to the unaltered key
	# @param block [Proc] the block to be applied to the key-value pairs of self
	# @return [Hash] the new Hash
	def map_hash(&block)
		self.merge(self){|k, v| block.call(k, v)}
	end

	# creates a new hash that has all keys casted to symbols
	# @return [Hash] the new Hash
	def symbolize_keys
		Hash[self.map{ |k, v| [k.to_sym, v] }]
	end

	# returns a new hash that is a copy of self, but without the given key(s)
	# @param keys [...] the key(s) to be removed
	# @return [Hash] the new Hash
	def except(*keys)
		reject{|k, v| keys.include?(k)}
	end

	# returns a hash that is a copy of self, but without the key whose values are nil
	# @return [Hash] the new Hash
	def compact
		self.select{|k, v| !v.nil? }
	end
end

class String
	def parse_parameters
		str = self.strip
		h = {
			:string => str,
			:attributes => {},
			:elements => [],
			:words => [],
			:all_nodes => [],
			:sections => [],
			:name_sequences => [],
			:nodes => [],
			:edges => [],
			:tokens => [],
			:ids => [],
		}

		r = {}
		r[:ctrl] = '(\s|:)'
		r[:comment] = '#'
		r[:bstring] = '[^\s:"#]+'
		#r[:qstring] = '"(([^"]*(\\\"[^"]*)*[^\\\])|)"'
		r[:qstring] = '"([^"]*(\\\"[^"]*)*([^"\\\]|\\\")|)"'
		r[:string] = '(' + r[:qstring] + '|' + r[:bstring] + ')'
		r[:sequence] = r[:string] + '\.\.' + r[:string]
		r[:attribute] = r[:string] + ':' + r[:string] + '?'
		r[:id] = '@' + '[_[:alnum:]]+'
		r.keys.each{|k| r[k] = Regexp.new('^' + r[k])}

		while str != ''
			m = nil
			if m = str.match(r[:comment])
				break
			elsif m = str.match(r[:ctrl])
			elsif m = str.match(r[:sequence])
				if mm = str.match(/^([ent])(\d+)\.\.\1(\d+)$/)
					([mm[2].to_i, mm[3].to_i].min..[mm[2].to_i, mm[3].to_i].max).each do |n|
						h[:elements] << mm[1] + n.to_s
						case str[0]
						when 'n'
							h[:nodes] << mm[1] + n.to_s
							h[:all_nodes] << mm[1] + n.to_s
						when 't'
							h[:tokens] << mm[1] + n.to_s
							h[:all_nodes] << mm[1] + n.to_s
						when 'e'
							h[:edges] << mm[1] + n.to_s
						end
					end
				else
					h[:name_sequences] << [
						m[2] ? m[2].gsub('\"', '"') : m[1],
						m[6] ? m[6].gsub('\"', '"') : m[5],
					]
				end
			elsif m = str.match(r[:attribute])
				key = m[2] ? m[2].gsub('\"', '"') : m[1]
				val = m[6] ? m[6].gsub('\"', '"') : m[5]
				h[:attributes][key] = val
			elsif m = str.match(r[:string])
				word = m[2] ? m[2].gsub('\"', '"') : m[1]
				h[:words] << word
				if word.match(/^(([ents]\d+)|m)$/)
					h[:elements] << word
					case word[0]
					when 'm', 's'
						h[:sections] << word
					when 'n'
						h[:nodes] << word
						h[:all_nodes] << word
					when 't'
						h[:tokens] << word
						h[:all_nodes] << word
					when 'e'
						h[:edges] << word
					end
				elsif word.match(r[:id])
					h[:ids] << word
				end
			else
				break
			end
			str = str[m[0].length..-1]
		end

		return h
	end

	def sql_json_escape_quotes
		self.gsub("'", "\\\\'").gsub('\\"', '\\\\\\"')
	end

	def is_hex_color?
		self.match(/^#[0-9a-fA-F]{6}$/)
	end

	def is_number?
		self.match(/^\s*-?[0-9]+\s*$/)
	end

	def de_escape!
		self.gsub!(/\\(.)/) do |s|
			case $1
			when '"'
				"\""
			when '\\'
				"\\"
			when 'a'
				"\a"
			when 'b'
				"\b"
			when 'n'
				"\n"
			when 'r'
				"\r"
			when 's'
				"\s"
			when 't'
				"\t"
			else
				$&
			end
		end
	end

	def xstrip(chars = nil)
		if !chars
			return self.strip
		else
			klasse = '[\u{'
			chars.each_char do |c|
				klasse += c.ord.to_s(16) + ' '
			end
			klasse = klasse[0..-2] + '}]'
			reg = Regexp.new('^' + klasse + '*(.*?)' + klasse + '*$')
			return self.sub(reg, '\1')
		end
	end

	def getmarker()
		if match = self.match(/\\(\S+)/)
			match[1].force_encoding('utf-8')
		else
			 nil
		end
	end

	def without_marker()
		self.partition(' ')[2].strip
	end

	def sanitize
		s = self.chars.map{|c| c.valid_encoding? ? c : '�'}.join
		if s == self
			return false
		else
			self.replace(s)
			return true
		end
	end
end
