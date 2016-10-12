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

require "unicode_utils/uppercase_char_q.rb"
require "unicode_utils/lowercase_char_q.rb"
require "unicode_utils/downcase.rb"
require "set.rb"
require 'yaml.rb'

require "punkt-segmenter/frequency_distribution.rb"
require "punkt-segmenter/punkt.rb"

class NLP
	@@languages = [
		'dutch',
		'english',
		'french',
		'german',
		'greek',
		'italian',
		'polish',
		'portuguese',
		'russian',
		'spanish',
		'swedish',
	]
	@@params = {}

	SentEndChars = ['.', '?', '!']
	ReSentEndChars = /[.?!]/
	InternalPunctuation = [',', ':', ';']
	ReBoundaryRealignment = /^["\')\]}]+?(?:\s+|(?=--)|$)/m
	ReWordStart = /[^\(\"\'„“”»«{\[:;&\#\*@\)}\]\-,]/
	ReNonWordChars = /(?:[?!)\"„“”»«;}\]\*:@\'’\({\[])/
	ReMultiCharPunct = /(?:\-{2,}|\.{2,}|(?:\.\s){2,}\.|–|—)/
	# soll es eine Wahlmöglichkeit geben, ob am Apostroph getrennt werden soll oder nicht?
	# ReApostrophedPart = /(?:[’\']\S+?)/
	# ReWordTokenizer = /#{ReMultiCharPunct}|(?=#{ReWordStart})\S+?#{ReApostrophedPart}?(?=\s|$|#{ReNonWordChars}|#{ReMultiCharPunct}|,(?=$|\s|#{ReNonWordChars}|#{ReMultiCharPunct}))|\S/
	ReWordTokenizer = /#{ReMultiCharPunct}|(?=#{ReWordStart})\S+?(?=\s|$|#{ReNonWordChars}|#{ReMultiCharPunct}|,(?=$|\s|#{ReNonWordChars}|#{ReMultiCharPunct}))|\S/

	def self.languages
		@@languages
	end

	def self.segment(s, lang)
		@@params[lang] = YAML.load(File.read("conf/nlp-params/#{lang}.yaml")) unless @@params[lang]
		segmenter = Punkt::SentenceTokenizer.new(@@params[lang])
		return segmenter.sentences_from_text(s, :output => :sentences_text)
	end

	def self.tokenize(s)
		tokens = []
		raw_tokens = s.scan(ReWordTokenizer)
		raw_tokens.each_with_index do |token, i|
			if SentEndChars.include?(token[-1]) and i == raw_tokens.length - 1 and not token.match(ReNonWordChars)
				tokens << token[0..-2]
				tokens << token[-1..-1]
			else
				tokens << token
			end
		end
		return tokens
	end

end
