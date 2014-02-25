# encoding: utf-8

# Copyright © 2014 Lennart Bierkandt <post@lennartbierkandt.de>
# 
# This file is part of GAST.
# 
# GAST is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# GAST is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with GAST. If not, see <http://www.gnu.org/licenses/>.

# Modul zum Importieren von Dependenzkorpora in Malt-XML
# ausgelegt für Perseus und PROIEL

class Anno_graph
	require 'rexml/document'

	def malt_einlesen(quelldatei)
		# Einstellungen
		ebene = 'f-layer'
		satzbezeichner = 'sentence'
		# "hartkodierte" Einstellungen
		satznamenpraefix = 'lat-'
		#datei = 'proieltest.xml'
		#satznamenpraefix += 'pro-att-'
		quelldatei = 'perseustest.xml'
		satznamenpraefix += 'per-cae-'
		
		xmldatei = File.read(quelldatei)
		xmldoc = REXML::Document.new(xmldatei)
		
		if xmldoc.root.attributes['xmlns:treebank'].match(/nlp.perseus.tufts.edu/)
			format = 'perseus'
		elsif xmldoc.root.attributes['xmlns:treebank'].match(/www.msi.vxu.se/)
			format = 'proiel'
		end
		
		case format
			when 'proiel'
				wortid = 'id'
				postag = 'morphology'
				wortform = 'form'
				lemma = 'lemma'
				relation = 'deprel'
				kopf = 'head'
			when 'perseus'
				wortid = 'id'
				postag = 'postag'
				wortform = 'form'
				lemma = 'lemma'
				kopf = 'head'
				relation = 'relation'
		end
		
		satznummer = 0
		xmldoc.elements.each('//sentence') do |satz|
			satzid = satznamenpraefix + "%03d"%satznummer
			knoten = {}
			# Token anlegen
			satz.elements.each('word') do |wort|
				# bei Proiel-Format: Wurzelknoten überspringen
				if wort.attributes[relation] == 'ROOT' then next end
				
				attr = {}
				attr[satzbezeichner] = satzid
				attr['token'] = wort.attributes[wortform]
				attr['lemma'] = wort.attributes[lemma]
				attr['postag'] = wort.attributes[postag]
				# Postag-Ersetzung:
				attr.merge!(parsePostag(attr['postag'], format))
				# Knoten anlegen (speichern in Hash knoten[] - id => knot)
				knoten[wort.attributes[wortid]] = self.add_node(:attr => attr)
			end
		
			# Kanten anlegen
			satz.elements.each('word') do |wort|
				# bei Proiel-Format: Wurzelknoten überspringen
				if wort.attributes[relation] == 'ROOT' then next end
				# wenn kein dominierender Knoten existiert: keine Kante erzeugen
				if !knoten[wort.attributes[kopf]] then next end
				
				attr = {}
				attr['elementid'] = wort.attributes[wortid]
				attr['cat'] = wort.attributes[relation]
				attr[ebene] = 't'
				attr[satzbezeichner] = satzid
				startknoten = knoten[wort.attributes[kopf]]
				zielknoten = knoten[wort.attributes[wortid]]
				# Kante anlegen
				self.add_edge(:type => 'g', :start => startknoten, :end => zielknoten, :attr => attr)
			end
			satznummer += 1
		end
	end

	def parsePostag(postag, format)
		h = {}
		if format == 'perseus'
			case postag[0] # Wortart
				when 'n' then h['pos'] = 'n' # noun
				when 'v' then h['pos'] = 'v' # verb
				when 't' then h['pos'] = 'v' # participle
				when 'a' then h['pos'] = 'adj' # adjective
				when 'd' then h['pos'] = 'adv' # adverb
				when 'c' then h['pos'] = 'conj' # conjunction
				when 'r' then h['pos'] = 'prep' # preposition
				when 'p' then h['pos'] = 'pro' # pronoun
				when 'm' then h['pos'] = 'num' # numeral
				when 'i' then h['pos'] = 'intj' # interjection
				when 'e' then h['pos'] = 'intj' # exclamation
				when 'u' then h['pos'] = 'pun' # punctuation
			end
			case postag[1] # Person (nur Verben)
				when '1' then h['agr'] = '1'
				when '2' then h['agr'] = '2'
				when '3' then h['agr'] = '3'
			end
			case postag[2] # Numerus 
				when 's'
					if postag[0] == 'v' 
						h['agr'] += '.sg'
					else
						h['num'] = 'sg'
					end
				when 'p'
					if postag[0] == 'v' 
						h['agr'] += '.pl'
					else
						h['num'] = 'pl'
					end
			end
			case postag[3] # Tempus
				when 'p' then h['tns'] = 'prs' # present
				when 'i' then h['tns'] = 'imp' # imperfect
				when 'r' then h['tns'] = 'prf' # perfect
				when 'l' then h['tns'] = 'plprf' # pluperfect
				when 't' then h['tns'] = 'futprf' # future perfect
				when 'f' then h['tns'] = 'fut' # future
			end
			case postag[4] # Modus / bei mir Formklasse
				when 'i' then h['fcl'] = 'ind' # indicative
				when 's' then h['fcl'] = 'sub' # subjunctive
				when 'n' then h['fcl'] = 'inf' # infinitive
				when 'm' then h['fcl'] = 'imp' # imperative
				when 'p' then h['fcl'] = 'ptcp' # participle
				when 'd' then h['fcl'] = 'ger' # gerund
				when 'g' then h['fcl'] = 'gdv' # gerundive
				when 'u' then h['fcl'] = 'sup' # supine
			end
			case postag[5] # Diathese
				when 'a' then h['alt'] = 'act'
				when 'p' then h['alt'] = 'pass'
			end
			case postag[6] # Genus
				when 'm', 'f', 'n' then h['gen'] = postag[6]
			end
			case postag[7] # Kasus
				when 'n' then h['cas'] = 'nom' # nominative
				when 'g' then h['cas'] = 'gen' # genitive
				when 'd' then h['cas'] = 'dat' # dative
				when 'a' then h['cas'] = 'acc' # accusative
				when 'b' then h['cas'] = 'abl' # ablative
				when 'v' then h['cas'] = 'voc' # vocative
				when 'l' then h['cas'] = 'loc' # locative
			end
			case postag[8] # Grad
				when 'c' then h['deg'] = 'comp'
				when 's' then h['deg'] = 'sup'
			end
		elsif format == 'claws5'
			postaghash = {
				'AJ0' => {'pos' => 'adj'}, # adjective (unmarked) (e.g. GOOD, OLD)
				'AJC' => {'pos' => 'adj'}, # comparative adjective (e.g. BETTER, OLDER)
				'AJS' => {'pos' => 'adj'}, # superlative adjective (e.g. BEST, OLDEST)
				'AT0' => {'pos' => 'art'}, # article (e.g. THE, A, AN)
				'AV0' => {'pos' => 'adv'}, # adverb (unmarked) (e.g. OFTEN, WELL, LONGER, FURTHEST)
				'AVP' => {'pos' => 'adv'}, # adverb particle (e.g. UP, OFF, OUT)
				'AVQ' => {'pos' => 'adv'}, # wh-adverb (e.g. WHEN, HOW, WHY)
				'CJC' => {'pos' => 'conj'}, # coordinating conjunction (e.g. AND, OR)
				'CJS' => {'pos' => 'conj'}, # subordinating conjunction (e.g. ALTHOUGH, WHEN)
				'CJT' => {'pos' => 'conj'}, # the conjunction THAT
				'CRD' => {'pos' => 'num'}, # cardinal numeral (e.g. 3, FIFTY-FIVE, 6609) (excl ONE)
				'DPS' => {'pos' => 'poss'}, # possessive determiner form (e.g. YOUR, THEIR)
				'DT0' => {'pos' => 'det'}, # general determiner (e.g. THESE, SOME)
				'DTQ' => {'pos' => 'det'}, # wh-determiner (e.g. WHOSE, WHICH)
				'EX0' => {'pos' => 'adv'}, # existential THERE
				'ITJ' => {'pos' => 'intj'}, # interjection or other isolate (e.g. OH, YES, MHM)
				'NN0' => {'pos' => 'n'}, # noun (neutral for number) (e.g. AIRCRAFT, DATA)
				'NN1' => {'pos' => 'n', 'num' => 'sg'}, # singular noun (e.g. PENCIL, GOOSE)
				'NN2' => {'pos' => 'n', 'num' => 'pl'}, # plural noun (e.g. PENCILS, GEESE)
				'NP0' => {'pos' => 'n', 'num' => 'sg'}, # proper noun (e.g. LONDON, MICHAEL, MARS)
				'NULL'=> {'pos' => 'x'}, # the null tag (for items not to be tagged)
				'ORD' => {'pos' => 'adj'}, # ordinal (e.g. SIXTH, 77TH, LAST)
				'PNI' => {'pos' => 'pro'}, # indefinite pronoun (e.g. NONE, EVERYTHING)
				'PNP' => {'pos' => 'pro'}, # personal pronoun (e.g. YOU, THEM, OURS)
				'PNQ' => {'pos' => 'pro'}, # wh-pronoun (e.g. WHO, WHOEVER)
				'PNX' => {'pos' => 'pro'}, # reflexive pronoun (e.g. ITSELF, OURSELVES)
				'POS' => {'pos' => 'adp'}, # the possessive (or genitive morpheme) 'S or '
				'PRF' => {'pos' => 'adp'}, # the preposition OF
				'PRP' => {'pos' => 'adp'}, # preposition (except for OF) (e.g. FOR, ABOVE, TO)
				'PUL' => {'pos' => 'pun'}, # punctuation - left bracket (i.e. ( or [ )
				'PUN' => {'pos' => 'pun'}, # punctuation - general mark (i.e. . ! , : ; - ? ... )
				'PUQ' => {'pos' => 'pun'}, # punctuation - quotation mark (i.e. ` ' " )
				'PUR' => {'pos' => 'pun'}, # punctuation - right bracket (i.e. ) or ] )
				'TO0' => {'pos' => 'ptcl', 'fcl' => 'to'}, # infinitive marker TO
				'UNC' => {'pos' => 'x'}, # "unclassified" items which are not words of the English lexicon
				'VBB' => {'pos' => 'v', 'vcl' => 'aux', 'fcl' => 'fin', 'tns' => 'prs'}, # the "base forms" of the verb "BE" (except the infinitive), i.e. AM, ARE
				'VBD' => {'pos' => 'v', 'vcl' => 'aux', 'fcl' => 'fin', 'tns' => 'pst'}, # past form of the verb "BE", i.e. WAS, WERE
				'VBG' => {'pos' => 'v', 'vcl' => 'aux', 'fcl' => 'ing'}, # -ing form of the verb "BE", i.e. BEING
				'VBI' => {'pos' => 'v', 'vcl' => 'aux', 'fcl' => 'inf'}, # infinitive of the verb "BE"
				'VBN' => {'pos' => 'v', 'vcl' => 'aux', 'fcl' => 'ppt'}, # past participle of the verb "BE", i.e. BEEN
				'VBZ' => {'pos' => 'v', 'vcl' => 'aux', 'fcl' => 'fin', 'tns' => 'prs', 'agr' => '3.sg'}, # -s form of the verb "BE", i.e. IS, 'S
				'VDB' => {'pos' => 'v', 'fcl' => 'fin', 'tns' => 'prs'}, # base form of the verb "DO" (except the infinitive), i.e.
				'VDD' => {'pos' => 'v', 'fcl' => 'fin', 'tns' => 'pst'}, # past form of the verb "DO", i.e. DID
				'VDG' => {'pos' => 'v', 'fcl' => 'ing'}, # -ing form of the verb "DO", i.e. DOING
				'VDI' => {'pos' => 'v', 'fcl' => 'inf'}, # infinitive of the verb "DO"
				'VDN' => {'pos' => 'v', 'fcl' => 'ppt'}, # past participle of the verb "DO", i.e. DONE
				'VDZ' => {'pos' => 'v', 'fcl' => 'fin', 'tns' => 'prs', 'agr' => '3.sg'}, # -s form of the verb "DO", i.e. DOES
				'VHB' => {'pos' => 'v', 'fcl' => 'fin', 'tns' => 'prs'}, # base form of the verb "HAVE" (except the infinitive), i.e. HAVE
				'VHD' => {'pos' => 'v', 'fcl' => 'fin', 'tns' => 'pst'}, # past tense form of the verb "HAVE", i.e. HAD, 'D
				'VHG' => {'pos' => 'v', 'fcl' => 'ing'}, # -ing form of the verb "HAVE", i.e. HAVING
				'VHI' => {'pos' => 'v', 'fcl' => 'inf'}, # infinitive of the verb "HAVE"
				'VHN' => {'pos' => 'v', 'fcl' => 'ppt'}, # past participle of the verb "HAVE", i.e. HAD
				'VHZ' => {'pos' => 'v', 'fcl' => 'fin', 'tns' => 'prs', 'agr' => '3.sg'},  # -s form of the verb "HAVE", i.e. HAS, 'S
				'VM0' => {'pos' => 'v', 'vcl' => 'mod', 'fcl' => 'fin'}, # modal auxiliary verb (e.g. CAN, COULD, WILL, 'LL)
				'VVB' => {'pos' => 'v', 'fcl' => 'fin', 'tns' => 'prs'}, # base form of lexical verb (except the infinitive)(e.g. TAKE, LIVE)
				'VVD' => {'pos' => 'v', 'fcl' => 'fin', 'tns' => 'pst'}, # past tense form of lexical verb (e.g. TOOK, LIVED)
				'VVG' => {'pos' => 'v', 'fcl' => 'ing'}, # -ing form of lexical verb (e.g. TAKING, LIVING)
				'VVI' => {'pos' => 'v', 'fcl' => 'inf'}, # infinitive of lexical verb
				'VVN' => {'pos' => 'v', 'fcl' => 'ppt'}, # past participle form of lex. verb (e.g. TAKEN, LIVED)
				'VVZ' => {'pos' => 'v', 'agr' => '3.sg'}, # -s form of lexical verb (e.g. TAKES, LIVES)
				'XX0' => {'pos' => 'ptcl', 'pol' => 'neg'},  # the negative NOT or N'T
				'ZZ0' => {'pos' => 'x'} # alphabetical symbol (e.g. A, B, c, d)
			}
			h = postaghash[postag]
		end
		return h
	end

end