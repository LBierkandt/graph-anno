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

# Modul zum Importieren von Dependenzkorpora in Malt-XML (Perseus) bzw. PROIEL-XML
# ausgelegt für Perseus und PROIEL

class Anno_graph
	require 'rexml/document'

	# Für PROIEL!!!
	def proiel_einlesen(quelldatei)
		puts 'Einlesen der Datei "' + quelldatei + '"...'
		# Einstellungen
		format = 'proiel'
		# "hartkodierte" Einstellungen
		satznamenpraefix = 'lat-'
		satznamenpraefix += 'cae-gall-'
		
		xmldatei = File.read(quelldatei)
		xmldoc = REXML::Document.new(xmldatei)
		
		# PROIEL-spezifisch
		wortid = 'id'
		postag = 'morph-features'
		wortform = 'form'
		kopf = 'head-id'
		relation = 'relation'

		title = xmldoc.elements['source/title'].text
		satznummer = 0
		xmldoc.elements.each('//div') do |div|
			section = div.elements['title'][0]
			div.elements.each('sentence') do |satz|
				satzid = satznamenpraefix + "%04d"%satznummer
				status = satz.attributes['status']
				# Meta-Knoten anlegen
				attr = {}
				attr['cat'] = 'meta'
				attr['sentence'] = satzid
				attr['title'] = title
				attr['section'] = section
				attr['status'] = status
				self.add_node(:attr => attr)
				
				# Knoten anlegen
				knoten = {}
				token = []
				satz.elements.each('token') do |wort|
					attr = {}
					attr['sentence'] = satzid
					attr['id'] = wort.attributes['id']
					
					if nicht_token = wort.attributes['empty-token-sort']
						attr['cat'] = nicht_token
						attr['f-layer'] = 't'
						attr['s-layer'] = 't'
						knoten[wort.attributes[wortid]] = self.add_node(:attr => attr)
					else
						attr['token'] = wort.attributes[wortform]
						# Postag-Ersetzung:
						attr.merge!(parse_postag(wort.attributes[postag], format))
						# Knoten anlegen (speichern in Hash knoten - {id.to_i => knot})
						knoten[wort.attributes[wortid]] = self.add_node(:attr => attr)
						token << knoten[wort.attributes[wortid]]
					end
					
				end
			
				# Kanten anlegen
				satz.elements.each('token') do |wort|
					# wenn kein dominierender Knoten existiert: keine Kante erzeugen
					if !knoten[wort.attributes[kopf]] then next end
					
					attr = {}
					attr['cat'] = wort.attributes[relation]
					attr['f-layer'] = 't'
					attr['s-layer'] = 't'
					attr['sentence'] = satzid
					# Kante anlegen
					self.add_edge(:type => 'g', :start => knoten[wort.attributes[kopf]], :end => knoten[wort.attributes[wortid]], :attr => attr)
					
					# "slash"-Kanten
					wort.elements.each('slashes/slash') do |kante|
						attr = {}
						attr['cat'] = kante.attributes['label']
						attr['f-layer'] = 't'
						attr['sentence'] = satzid
							self.add_edge(:type => 'g', :start => knoten[wort.attributes[wortid]], :end => knoten[kante.attributes['target']], :attr => attr)
					end
				end
				
				# Token verbinden
				token[0..-2].each_with_index do |tok, i|
					self.add_edge(:type => 't', :start => token[i], :end => token[i+1], :attr => {'sentence' => satzid})
				end
				satznummer += 1
			end
		end
	end

	# Für Perseus!!!
	def malt_einlesen(quelldatei)
		# Einstellungen
		ebene = 'f-layer'
		format = 'perseus'
		# "hartkodierte" Einstellungen
		quelldatei = 'perseustest.xml'
		satznamenpraefix = 'lat-'
		satznamenpraefix += 'per-cae-'
		
		xmldatei = File.read(quelldatei)
		xmldoc = REXML::Document.new(xmldatei)
		
		# Perseus-spezifisch
		wortid = 'id'
		postag = 'postag'
		wortform = 'form'
		lemma = 'lemma'
		kopf = 'head'
		relation = 'relation'
		
		satznummer = 0
		xmldoc.elements.each('//sentence') do |satz|
			satzid = satznamenpraefix + "%03d"%satznummer
			knoten = {}
			# Token anlegen
			satz.elements.each('word') do |wort|
				attr = {}
				attr['sentence'] = satzid
				attr['token'] = wort.attributes[wortform]
				attr['lemma'] = wort.attributes[lemma]
				attr['postag'] = wort.attributes[postag]
				# Postag-Ersetzung:
				attr.merge!(parse_postag(attr['postag'], format))
				# Knoten anlegen (speichern in Hash knoten - {id => knot})
				knoten[wort.attributes[wortid]] = self.add_node(:attr => attr)
			end
		
			# Kanten anlegen
			satz.elements.each('word') do |wort|
				# wenn kein dominierender Knoten existiert: keine Kante erzeugen
				if !knoten[wort.attributes[kopf]] then next end
				
				attr = {}
				attr['cat'] = wort.attributes[relation]
				attr[ebene] = 't'
				attr['sentence'] = satzid
				startknoten = knoten[wort.attributes[kopf]]
				zielknoten = knoten[wort.attributes[wortid]]
				# Kante anlegen
				self.add_edge(:type => 'g', :start => startknoten, :end => zielknoten, :attr => attr)
			end
			satznummer += 1
		end
	end

	def proiel2etlas
		puts 'Umwandeln in ETLAS...'
		self.dep2ps
		@edges.values.each do |k|
			case k.cat
			when 'pid'
				k.cat = 'PR'
				if k.end.child_nodes{|e| e.cat == 'pr'} != []
					k.end = k.end.child_nodes{|e| e.cat == 'pr'}[0]
				end
				k.start.attr.merge!(k.end.attr.reject{|s,w| ['token', 'id', 'postag'].include?(s)})
			#when 'aux'
			#	k.cat = 'OP'
			end
		end
		self.merkmale_projizieren(nil, 'conf/feature_projection_proiel.yaml')
	end

	def dep2ps
		@nodes.values.select{|k| k.token}.each do |tok|
			if tok.out.select{|k| k.type == 'g'}.length > 0
				attr = {}
				attr['sentence'] = tok.sentence
				attr['f-layer'] = 't'
				attr['s-layer'] = 't'
				#attr.merge!(tok.attr.reject{|s,w| ['token', 'id', 'postag'].include?(s)})
				neuer_knoten = self.add_node(:attr => attr)
				tok.out.select{|k| k.type == 'g'}.each do |k|
					k.start = neuer_knoten
				end
				tok.in.select{|k| k.type == 'g'}.each do |k|
					k.end = neuer_knoten
				end
				attr = {}
				attr['cat'] = 'pr'
				attr['sentence'] = tok.sentence
				attr['f-layer'] = 't'
				attr['s-layer'] = 't'
				self.add_edge(:type => 'g', :start => neuer_knoten, :end => tok, :attr => attr)
			end
		end
	end

	def parse_postag(postag, format)
		h = {}
		case format
		when 'perseus'
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
		when 'proiel'
			h = {}
			if !postag then return h end
			teile = postag.split(',')
			h['lemma'] = teile[0]
			h['pos'] = teile[1]
			postag = teile[3]
			h['postag'] = postag
			#case postag[0] # Wortart
			#	when 'n' then h['pos'] = 'n' # noun
			#	when 'v' then h['pos'] = 'v' # verb
			#	when 't' then h['pos'] = 'v' # participle
			#	when 'a' then h['pos'] = 'adj' # adjective
			#	when 'd' then h['pos'] = 'adv' # adverb
			#	when 'c' then h['pos'] = 'conj' # conjunction
			#	when 'r' then h['pos'] = 'prep' # preposition
			#	when 'p' then h['pos'] = 'pro' # pronoun
			#	when 'm' then h['pos'] = 'num' # numeral
			#	when 'i' then h['pos'] = 'intj' # interjection
			#	when 'e' then h['pos'] = 'intj' # exclamation
			#	when 'u' then h['pos'] = 'pun' # punctuation
			#end
			case postag[0] # Person (nur Verben)
				when '1' then h['agr'] = '1'
				when '2' then h['agr'] = '2'
				when '3' then h['agr'] = '3'
			end
			case postag[1] # Numerus 
				when 's'
					if h['agr']
						h['agr'] += '.sg'
					else
						h['num'] = 'sg'
					end
				when 'p'
					if h['agr']
						h['agr'] += '.pl'
					else
						h['num'] = 'pl'
					end
			end
			case postag[2] # Tempus
				when 'p' then h['tns'] = 'prs' # present
				when 'i' then h['tns'] = 'imp' # imperfect
				when 'r' then h['tns'] = 'prf' # perfect
				when 'l' then h['tns'] = 'plprf' # pluperfect
				when 't' then h['tns'] = 'futprf' # future perfect
				when 'f' then h['tns'] = 'fut' # future
			end
			case postag[3] # Modus / bei mir Formklasse
				when 'i' then h['fcl'] = 'ind' # indicative
				when 's' then h['fcl'] = 'sub' # subjunctive
				when 'n' then h['fcl'] = 'inf' # infinitive
				when 'm' then h['fcl'] = 'imp' # imperative
				when 'p' then h['fcl'] = 'ptcp' # participle
				when 'd' then h['fcl'] = 'ger' # gerund
				when 'g' then h['fcl'] = 'gdv' # gerundive
				when 'u' then h['fcl'] = 'sup' # supine
			end
			case postag[4] # Diathese
				when 'a' then h['alt'] = 'act'
				when 'p' then h['alt'] = 'pass'
			end
			case postag[5] # Genus
				when 'm', 'f', 'n' then h['gen'] = postag[5]
			end
			case postag[6] # Kasus
				when 'n' then h['cas'] = 'nom' # nominative
				when 'g' then h['cas'] = 'gen' # genitive
				when 'd' then h['cas'] = 'dat' # dative
				when 'a' then h['cas'] = 'acc' # accusative
				when 'b' then h['cas'] = 'abl' # ablative
				when 'v' then h['cas'] = 'voc' # vocative
				when 'l' then h['cas'] = 'loc' # locative
			end
			case postag[7] # Grad
				when 'c' then h['deg'] = 'comp'
				when 's' then h['deg'] = 'sup'
			end
		end
		return h
	end

end

