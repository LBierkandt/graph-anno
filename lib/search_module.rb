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

require_relative 'parser_module'

class Graph
# Suchmethoden

	require 'unicode_utils/downcase'
	require 'csv'

	def teilgraph_suchen(anfrage)
		operationen = anfrage.parse_query
		
		puts 'Searching for graph fragment ...'
		startzeit = Time.new
		
		suchgraph = self.clone
		tglisten = {}
		gefundene_tg = []
		id_index = {}
		tgindex = 0
		
		# Vorgehen:
		# Anfrage auf Wohlgeformtheit prüfen
		# edge in link umwandeln, wenn :start und :end gegeben
		# meta: zu durchsuchenden Graph einschränken
		# edge ohne :start und :end suchen
		# node/nodes: passende Knoten jeweils als TG
		# text: Textfragmente
		# edge/link: node/nodes-TGn und text-TGn kombinieren
		
		# Validität der Anfrage prüfen
		# mindestens eine node-, edge- oder oder text-Klausel
		if operationen['node'] + operationen['edge'].select{|o| !(o[:start] or o[:end])} + operationen['text'] == []
			raise 'Die Anfrage muß mindest eine node-, edge- oder oder text-Klausel enthalten.'
		end
		# keine nicht definierten IDs als Start und Ziel bzw. in Bedingungen
		erlaubte_start_end_ids =
			operationen['node'].map{|o| o[:id]} + operationen['nodes'].map{|o| o[:id]} + operationen['text'].map{|o| o[:id]} + operationen['text'].map{|o| o[:ids]}.flatten
		benutzte_start_end_ids =
			(operationen['edge'].map{|o| [o[:start], o[:end]]} + operationen['link'].map{|o| [o[:start], o[:end]]}).flatten.compact
		als_referenz_erlaubte_ids = 
			erlaubte_start_end_ids + operationen['edge'].map{|o| o[:id]} + operationen['link'].map{|o| o[:ids]}.flatten
		als_referenz_benutzte_ids = operationen['cond'].map{|o| o[:ids].values}.flatten
		benutzte_start_end_ids.each do |id|
			if not erlaubte_start_end_ids.include?(id)
				raise "Die ID #{id} wurde als Start oder Ziel verwendet, ist aber nicht definiert."
			end
		end
		als_referenz_benutzte_ids.each do |id|
			if not als_referenz_erlaubte_ids.include?(id)
				raise "Die ID #{id} wurde in cond verwendet, ist aber nicht definiert."
			end
		end
		# Zusammenhängendes Graphfragment?
		if benutzte_start_end_ids.length > 0 and !erlaubte_start_end_ids.any?{|id| benutzte_start_end_ids.include?(id)}
			raise "Kein zusammenh\u00E4ngendes Graphfragment."
		end
		
		# edge in link umwandeln, wenn Start und Ziel gegeben
		operationen['edge'].clone.each do |operation|
			if operation[:start] and operation[:end]
				operationen['link'] << {
					:operator => 'edge',
					:start => operation[:start],
					:end   => operation[:end],
					:arg   => operation.reject{|s,w| [:start, :end].include?(s)},
					:ids   => [operation[:id]].compact
				}
				operationen['edge'].delete(operation)
			end
		end
		
		# meta
		# hier wird ggf. der zu durchsuchende Graph eingeschränkt
		if metabedingung = operation_erzeugen(:op => 'and', :arg => operationen['meta'].map{|op| op[:cond]})
			metaknoten = @nodes.values.select{|k| k.cat == 'meta' && k.fulfil?(metabedingung)}
			satznamen = metaknoten.map{|k| k.sentence}
			suchgraph.nodes.select!{|id,k| satznamen.include?(k.sentence)}
			suchgraph.edges.select!{|id,k| satznamen.include?(k.sentence)}
		end
		
		# edge
		operationen['edge'].each do |operation|
			gefundene_kanten = suchgraph.edges.values.select{|k| k.fulfil?(operation[:cond])}
			tglisten[tgindex += 1] = gefundene_kanten.map do |k|
				neu = Teilgraph.new
				neu.edges << k
				neu.ids[operation[:id]] = [k]
				neu
			end
			id_index[operation[:id]] = {:index => tgindex, :art => operation[:operator], :cond => operation[:cond]}
		end
		
		# node/nodes
		# gefundene Knoten werden als atomare Teilgraphen gesammelt
		(operationen['node'] + operationen['nodes']).each do |operation|
			gefundene_knoten = suchgraph.nodes.values.select{|k| k.fulfil?(operation[:cond])}
			tglisten[tgindex += 1] = gefundene_knoten.map do |k|
				neu = Teilgraph.new
				neu.nodes << k
				neu.ids[operation[:id]] = [k]
				neu
			end
			if operation[:operator] == 'nodes'
				dummytg = Teilgraph.new
				dummytg.ids[operation[:id]] = []
				tglisten[tgindex] << dummytg
			end
			id_index[operation[:id]] = {:index => tgindex, :art => operation[:operator], :cond => operation[:cond]}
		end
		
		# text
		# ein oder mehrer Teilgraphenlisten werden erstellt
		operationen['text'].each do |operation|
			tglisten[tgindex += 1] = suchgraph.textsuche_NFA(operation[:arg], operation[:id])
			# id_index führen
			if operation[:id]
				id_index[operation[:id]] = {:index => tgindex, :art => operation[:operator]}
			end
			operation[:ids].each do |id|
				id_index[id] = {:index => tgindex, :art => operation[:operator]}
			end
		end
		
		# link
		# atomare Teilgraphen werden zu Ketten verbunden
		operationen['link'].sort{|a,b| link_operation_vergleichen(a, b, id_index)}.each_with_index do |operation,operationsindex|
			startid = operation[:start]
			zielid = operation[:end]
			if !id_index[startid] || !id_index[zielid] then next end
			startindex = id_index[startid][:index]
			zielindex = id_index[zielid][:index]
			tgl_start = tglisten[startindex]
			tgl_ziel = tglisten[zielindex]
			schon_gesucht = {}
			neue_tgl = []
			
			automat = Automat.create(operation[:arg])
			automat.bereinigen
			#automat.zustaende.each{|z| puts z; puts z.typ; puts z.uebergang; puts z.folgezustand; puts}
			
			if id_index[startid][:art] != 'text'
				if id_index[zielid][:art] != 'text'
					# erstmal node(s) -> node(s)
					tgl_start.each do |starttg|
						startknot = starttg.ids[startid][0]
						if !(breitensuche = schon_gesucht[startknot])
							breitensuche = startknot.links(automat, id_index[zielid][:cond])
							if breitensuche == [] then breitensuche = [[nil, Teilgraph.new]] end
							schon_gesucht[startknot] = breitensuche
						end
						breitensuche.each do |zielknot, pfadtg|
							if startindex != zielindex # wenn Start und Ziel in verschiedenen TGLn
								zieltgn = tgl_ziel.select{|tg| tg.ids[zielid][0] == zielknot}
								zieltgn.each do |zieltg|
									neue_tgl << starttg + pfadtg + zieltg
								end
							else # wenn Start und Ziel in selber TGL
								if starttg.ids[zielid][0] == zielknot
									neue_tgl << starttg + pfadtg
								end
							end
						end
					end
				else # wenn Ziel 'text' ist
					tgl_start.each do |starttg|
						startknot = starttg.ids[startid][0]
						if !(breitensuche = schon_gesucht[startknot])
							breitensuche = startknot.links(automat, {:operator => 'attr', :key => 'token'}) # Zielknoten muß Token sein
							schon_gesucht[startknot] = breitensuche
						end
						if startindex != zielindex # wenn Start und Ziel in verschiedenen TGLn
							zieltgn = tgl_ziel.select{|tg| tg.ids[zielid] - breitensuche.map{|knot, pfad| knot} == []}
							zieltgn.each do |zieltg|
								pfadtg = breitensuche.select{|knot, pfad| zieltg.ids[zielid].include?(knot)}.map{|knot, pfad| pfad}.reduce(:+)
								neue_tgl << starttg + pfadtg + zieltg
							end
						else # wenn Start und Ziel in selber TGL
							if starttg.ids[zielid] - breitensuche.map{|knot, pfad| knot} == []
								pfadtg = breitensuche.select{|knot, pfad| zieltg.ids[zielid].include?(knot)}.map{|knot, pfad| pfad}.reduce(:+)
								neue_tgl << starttg + pfadtg
							end
						end
					end
				end
			else # wenn Start 'text' ist
			end
			
			# alte tg-Listen löschen
			tglisten.delete(startindex)
			tglisten.delete(zielindex)
			# neue einfügen
			tglisten[tgindex += 1] = neue_tgl
			# link-IDs in id_index
			operation[:ids].each do |id|
				id_index[id] = {:index => tgindex, :art => operation[:operator]}
			end
			# id_index auffrischen
			id_index.each do |id,tgi|
				if tgi[:index] == startindex || tgi[:index] == zielindex then id_index[id][:index] = tgindex end
			end
			# Operation löschen
			operationen['link'].delete_at(operationsindex)
		end
		
		# Teilgraphen zusammenfassen, und zwar dann, wenn sie alle ihre "node"-Knoten bzw. "text"e teilen
		if operationen['nodes'] != []
			node_indizes = id_index.select{|s,w| w[:art] == 'node' || w[:art] == 'text'}
			# für jede TG-Liste, die "node"s oder "text"e enthält:
			node_indizes.values.map{|h| h[:index]}.uniq.each do |node_tgindex|
				node_ids = node_indizes.select{|s,w| w[:index] == node_tgindex}.keys
				tgliste = tglisten[node_tgindex]
				neue_tgl = []
				until tgliste.length == 0
					referenztg = tgliste.slice!(0)
					# "node"s/"text"e des Referenz-TG
					node_knoten = referenztg.ids.select{|s,w| node_ids.include?(s)}.values.map{|k| k.sort{|a,b| a.ID.to_i <=> b.ID.to_i}}
					zusammengefasst = Teilgraph.new
					# TGn aus der Liste nehmen und mit Referenz-TG zusammenführen, wenn gleiche "node"s/"text"e
					tgliste.clone.each do |tg|
						if node_knoten == tg.ids.select{|s,w| node_ids.include?(s)}.values.map{|k| k.sort{|a,b| a.ID.to_i <=> b.ID.to_i}} # sortieren, damit auch Textfragmente verglichen werden können
							zusammengefasst += tgliste.delete(tg)
						end
					end
					neue_tgl << zusammengefasst + referenztg
				end
				# alte tg-Liste löschen
				tglisten.delete(node_tgindex)
				# neue einfügen
				tglisten[tgindex += 1] = neue_tgl.reverse
				# id_index auffrischen
				id_index.each do |id,tgi|
					if tgi == node_tgindex then id_index[id] = tgindex end
				end
			end
		end
		
		## Zusammenhängendes Graphfragment? Sollte vielleicht besser vor der Suche geprüft werden. Wird es jetzt auch.
		#if tglisten.length > 1
		#	puts 'Achtung: Sie haben kein zusammenhängendes Graphfragment angegeben!'
		#end
		
		tgliste = tglisten.values.flatten(1)
		
		# cond
		operationen['cond'].each do |op|
			lambda = evallambda(op, id_index)
			tgliste.select!{|tg| lambda.call(tg)}
		end
		
		puts "Found #{tgliste.length.to_s} matches in #{(Time.new - startzeit).to_s} seconds"
		puts
		
		return {:tg => tgliste, :id_type => id_index.map_hash{|s,w| w[:art]}}
	end

	def textsuche_NFA(operation, id = nil) 
		automat = Automat.create(operation)
		automat.bereinigen
		
		# Grenzknoten einbauen (das muß natürlich bei einem Graph mit verbundenen Sätzen und mehreren Ebenen anders aussehen)
		grenzknoten = []
		@nodes.values.select{|k| k.token}.each do |tok|
			if !tok.token_before
				grenzknoten << self.add_node(:attr => {'token' => '', 'cat' => 'boundary', 'level' => 's'})
				self.add_edge(:type => 't', :start => grenzknoten.last, :end => tok)
			end
			if !tok.token_after
				grenzknoten << self.add_node(:attr => {'token' => '', 'cat' => 'boundary', 'level' => 's'})
				self.add_edge(:type => 't', :start => tok, :end => grenzknoten.last)
			end
		end
		
		ergebnis = []
		@nodes.values.select{|k| k.token}.each do |node|
			if t = automat.text_suchen_ab(node) 
				ergebnis << t
			end
		end
		if id
			ergebnis.each do |tg|
				tg.ids[id] = tg.nodes.clone
			end
		end
		
		# Grenzknoten wieder entfernen
		grenzknoten.each do |node|
			node.delete
		end
		
		return ergebnis
	end

	def link_operation_vergleichen(a, b, id_index)
		# sortiert so, daß zuerst node-node-Verbindungen kommen, dann node-anderes oder anderes-node und dann anderes-anderes
		wert_a = ([id_index[a[:start]][:art], id_index[a[:end]][:art]] - ['node']).length
		wert_b = ([id_index[b[:start]][:art], id_index[b[:end]][:art]] - ['node']).length
		return wert_a - wert_b
	end

	def operation_erzeugen(p)
		case p[:op]
		when 'and', 'or'
			if p[:arg].length == 2
				return {:operator => p[:op], :arg => p[:arg]}
			elsif p[:arg].length < 2
				return p[:arg][0]
			else
				return {:operator => p[:op], :arg => [p[:arg][0], operationen_verknuepfen(:op => p[:op], :arg => p[:arg][1..-1])]}
			end
		when 'not' # wenn mehr als ein Argument: not(arg1 or arg2 or ...)
			if p[:arg].length == 1
				return {:operator => p[:op], :arg => p[:arg][0]}
			elsif p[:arg].length == 0
				return nil
			else
				return {:operator => p[:op], :arg => [operationen_verknuepfen(:op => 'or', :arg => p[:arg])]}
			end
		end
	end

	def evallambda(op, id_index)
		string = op[:string].clone
		op[:ids].keys.sort{|a,b| b.begin <=> a.begin}.each do |stelle|
			id = op[:ids][stelle]
			if (id_type = id_index[id]).class == Hash then id_type = id_index[id][:art] end
			case id_type
				when 'node', 'edge'
					string[stelle] = 'tg.ids["' + id + '"][0]'
				when 'nodes', 'text', 'link'
					string[stelle] = 'tg.ids["' + id + '"]'
			end
		end
		string = 'lambda{|tg| ' + string + '}'
		begin
			rueck = eval(string)
		rescue SyntaxError
			rueck = eval('lambda{|tg| "error!"}')
			raise "Syntaxfehler in Zeile:\n#{op[:operator]} #{op[:title] ? op[:title] : ''} #{op[:string]}"
		end
		return rueck
	end

end

class NodeOrEdge

	def fulfil?(bedingung)
		if bedingung.class == String
			bedingung = bedingung.parse_attributes[:op]
		end
		if not bedingung then return true end
		satzzeichen = '.,;:?!"'
		case bedingung[:operator]
		when 'attr'
			knotenwert = @attr[bedingung[:key]]
			if !knotenwert then return false end
			wert = bedingung[:value]
			if !wert then return true end
			case bedingung[:method]
			when 'plain'
				if knotenwert == wert then return true end
			when 'insens'
				if bedingung[:key] == 'token'
					if UnicodeUtils.downcase(knotenwert.xstrip(satzzeichen)) == UnicodeUtils.downcase(wert) then return true end
				else
					if UnicodeUtils.downcase(knotenwert) == UnicodeUtils.downcase(wert) then return true end
				end
			when 'regex'
				if knotenwert.match(wert) then return true end
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
			if self.kind_of?(Node)
				return @in.select{|k| k.fulfil?(bedingung[:cond])}.length
			else
				return 1
			end
		when 'out'
			if self.kind_of?(Node)
				return @out.select{|k| k.fulfil?(bedingung[:cond])}.length
			else
				return 1
			end
		when 'link'
			if self.kind_of?(Node)
				return self.links(bedingung[:arg]).length
			else
				return 1
			end
		when 'start'
			if self.kind_of?(Edge) && !@start.fulfil?(bedingung[:cond])
				return false
			else
				return true
			end
		when 'end'
			if self.kind_of?(Edge) && !@end.fulfil?(bedingung[:cond])
				return false
			else
				return true
			end
		else
			return true
		end
	end

end

class Node

	def links(pfad_oder_automat, zielknotenbedingung = nil)
		if pfad_oder_automat.class == String
			automat = Automat.create(pfad_oder_automat.parse_link[:op])
			automat.bereinigen
		elsif pfad_oder_automat.class == Automat
			automat = pfad_oder_automat
		else
			automat = Automat.create(pfad_oder_automat)
			automat.bereinigen
		end
	
		neue_zustaende = [{:zustand => automat.startzustand, :tg => Teilgraph.new, :el => self, :forward => true}]
		rueck = []
		
		loop do   # Kanten und Knoten durchlaufen
			alte_zustaende = neue_zustaende.clone
			neue_zustaende = []
			
			alte_zustaende.each do |z|
				# Ziel gefunden?
				if z[:zustand] == nil
					if z[:el].kind_of?(Node)
						if z[:el].fulfil?(zielknotenbedingung)
							rueck << [z[:el], z[:tg]]
						# wenn z[:zustand] == nil und keinen Zielknoten gefunden, dann war's eine Sackgasse
						end
					else # wenn zuende gesucht, aber Edge aktuelles Element: Zielknoten prüfen!
						if zielknotenbedingung
							z[:tg].edges << z[:el]
							if z[:forward]
								neue_zustaende += automat.schrittliste_graph(z.update({:el => z[:el].end}).clone)
							else
								neue_zustaende += automat.schrittliste_graph(z.update({:el => z[:el].start}).clone)
							end
						else # wenn keine zielknotenbedingung dann war der letzte gefundene Knoten schon das Ziel
							letzer_knoten = z[:forward] ? z[:el].start : z[:el].end
							rueck << [letzer_knoten, z[:tg]]
						end
					end
				else # wenn z[:zustand] != nil
					neue_zustaende += automat.schrittliste_graph(z.update({:tg => z[:tg].clone}).clone)
				end
			end
			if neue_zustaende == []
				return rueck
			end
		end
	end

	def nodes(link, zielknotenbedingung = '')
		return links(link, zielknotenbedingung.parse_attributes[:op]).map{|knot, pfad| knot}.unique
	end

end

class Automat
	attr_accessor :zustaende
	
	def self.create(operation, ids = [])
		ids = ids.clone
		if operation[:id] then ids << operation[:id] end
		case operation[:operator]
		when 'node'
			return Automat.new(Zustand.new('node', nil, operation[:cond], ids))
		when 'edge'
			return Automat.new(Zustand.new('edge', nil, operation[:cond], ids))
		when 'redge'
			return Automat.new(Zustand.new('redge', nil, operation[:cond], ids))
		when 'boundary'
			return Automat.new(Zustand.new('node', nil, ('cat:"boundary" & level:'+operation[:level]).parse_attributes[:op]))
		when 'or'
			folgeautomaten = [Automat.create(operation[:arg][0], ids), Automat.create(operation[:arg][1], ids)]
			automat = Automat.new(Zustand.new('split', [], ids))
			automat.anhaengen(folgeautomaten[0])
			automat.anhaengen(folgeautomaten[1])
			automat.startzustand.folgezustand << folgeautomaten[0].startzustand
			automat.startzustand.folgezustand << folgeautomaten[1].startzustand
			return automat
		when 'seq'
			erster_automat = Automat.create(operation[:arg][0], ids)
			zweiter_automat = Automat.create(operation[:arg][1], ids)
			erster_automat.automaten_anhaengen(zweiter_automat)
			return erster_automat
		when 'quant'
			automat = Automat.new(Zustand.new('empty', nil, ids))
			(1..operation[:min]).each do |i|
				automat.automaten_anhaengen(Automat.create(operation[:arg], ids))
			end
			if operation[:max] > operation[:min]
				splitautomat = nil
				(1..operation[:max] - operation[:min]).each do |i|
					splitautomat = Automat.new(Zustand.new('split', [], ids))
					anhangautomat = Automat.create(operation[:arg], ids)
					leerautomat = Automat.new(Zustand.new('empty', nil, ids))
					
					splitautomat.anhaengen(leerautomat)
					splitautomat.anhaengen(anhangautomat)
					
					splitautomat.startzustand.folgezustand << leerautomat.startzustand
					splitautomat.startzustand.folgezustand << anhangautomat.startzustand
					
					automat.automaten_anhaengen(splitautomat)
				end
			elsif operation[:max] < 0
				splitautomat = Automat.new(Zustand.new('split', [], ids))
				
				leerautomat = Automat.new(Zustand.new('empty', nil, ids))
				anhangautomat = Automat.create(operation[:arg], ids)
				anhangautomat.automaten_anhaengen(splitautomat)
				
				splitautomat.anhaengen(leerautomat)
				splitautomat.anhaengen(anhangautomat)
				
				splitautomat.startzustand.folgezustand << leerautomat.startzustand
				splitautomat.startzustand.folgezustand << anhangautomat.startzustand
				
				automat.automaten_anhaengen(splitautomat)
			end
			return automat
		end
	end
	
	def initialize(startzust = nil)
		@zustaende = [startzust].compact
	end
	
	def startzustand
		return @zustaende[0]
	end
	
	def automaten_anhaengen(neuer_automat)
		@zustaende.each do |z|
				if z.folgezustand == nil then z.folgezustand = neuer_automat.startzustand end
		end
		self.anhaengen(neuer_automat)
	end
	
	def anhaengen(neuer_automat)
		@zustaende += neuer_automat.zustaende
	end
	
	def bereinigen
		@zustaende = @zustaende.uniq
		@zustaende.clone.each do |z|
			if z.typ == 'empty'
				@zustaende.each_with_index do |zz,i|
					if zz.folgezustand == z
						@zustaende[i].folgezustand = z.folgezustand
					elsif zz.folgezustand.class == Array
						zz.folgezustand.each_with_index do |fz,ii|
							if fz == z then @zustaende[i].folgezustand[ii] = z.folgezustand end
						end
					end
				end
				@zustaende.delete(z)
			end
		end
	end

	def text_suchen_ab(startknoten)
		neue_zustaende = [{:zustand => self.startzustand, :tg => Teilgraph.new}]
		neuer_knoten = startknoten
		
		loop do   # Knoten durchlaufen
			alte_zustaende = neue_zustaende.clone
			neue_zustaende = []
			
			alte_zustaende.each do |z|
				# Text gefunden?
				if z[:zustand] == nil then return z[:tg] end
				# sonst nächsten Schritt
				neue_zustaende += schrittliste_text(z[:zustand], z[:tg], neuer_knoten)
			end
			if neue_zustaende == [] then return nil end
		
			# Weiter vorrücken im Text
			neuer_knoten = neuer_knoten.token_after
		end
	end

	def schrittliste_text(z, tg, nk)
		# Liste von Folgezuständen erstellen
		if z == nil then return [{:zustand => nil, :tg => tg}] end
		liste = []
		case z.typ
		when 'split'
			liste += schrittliste_text(z.folgezustand[0], tg.clone, nk)
			liste += schrittliste_text(z.folgezustand[1], tg.clone, nk)
		when 'empty'
			liste += schrittliste_text(z.folgezustand, tg, nk)
		when 'node'
			if nk && nk.fulfil?(z.uebergang)
				tg.nodes << nk
				z.ids.each do |id|
					tg.element_zu_id_hinzufuegen(id, nk)
				end
				liste << {:zustand => z.folgezustand, :tg => tg}
			end
		end
		return liste
	end

	def schrittliste_graph(h)
		z = h[:zustand]
		tg = h[:tg]
		nk = h[:el]
		forward = h[:forward]
		# Liste von Folgezuständen erstellen
		if z == nil then return [h] end
		liste = []
		case z.typ
		when 'split'
			liste += schrittliste_graph(:zustand=>z.folgezustand[0], :tg=>tg.clone, :el=>nk, :forward=>forward)
			liste += schrittliste_graph(:zustand=>z.folgezustand[1], :tg=>tg.clone, :el=>nk, :forward=>forward)
		when 'empty'
			liste += schrittliste_graph(:zustand=>z.folgezustand, :tg=>tg, :el=>nk, :forward=>forward)
		when 'node'
			if nk.kind_of?(Node)
				if nk.fulfil?(z.uebergang) then schritt_in_liste(h.clone, liste) end
			elsif forward # wenn das aktuelle Element eine Kante ist
				schritt_in_liste(h.clone, liste, false)
			end
		when 'edge'
			if nk.kind_of?(Edge)
				if forward and nk.fulfil?(z.uebergang) then schritt_in_liste(h.clone, liste) end
			else # wenn das aktuelle Element ein Knoten ist
				schritt_in_liste(h.clone, liste, false)
			end
		when 'redge'
			if nk.kind_of?(Edge)
				if !forward and nk.fulfil?(z.uebergang) then schritt_in_liste(h.clone, liste) end
			else # wenn das aktuelle Element ein Knoten ist
				schritt_in_liste(h.clone, liste, false)
			end
		end
		return liste
	end

	def schritt_in_liste(h, liste, schritt = true)
		z = h[:zustand]
		tg = h[:tg]
		nk = h[:el]
		forward = h[:forward]
		if tg.nodes.include?(nk) then return end # zirkuläre Pfade werden ausgeschlossen
		if schritt
			z.ids.each do |id|
				tg.element_zu_id_hinzufuegen(id, nk)
			end
			naechster_zustand = z.folgezustand
		else
			naechster_zustand = z
		end
		if nk.kind_of?(Node)
			tg.nodes << nk
			nk.out.select{|k| k.type == 'g'}.each do |auskante|
				liste << {:zustand => naechster_zustand, :tg => tg, :el => auskante, :forward => true}
			end
			nk.in.select{|k| k.type == 'g'}.each do |einkante|
				liste << {:zustand => naechster_zustand, :tg => tg, :el => einkante, :forward => false}
			end
		else # wenn nk eine Kante ist
			tg.edges << nk
			if forward
				liste << {:zustand => naechster_zustand, :tg => tg, :el => nk.end, :forward => true}
			else
				liste << {:zustand => naechster_zustand, :tg => tg, :el => nk.start, :forward => true}
			end
		end
	end
end

class Zustand
	attr_accessor :typ, :folgezustand, :uebergang, :ids
	
	def initialize(typ, folgezustand = nil, uebergang = nil, ids = [])
		@typ = typ
		@folgezustand = folgezustand
		@uebergang = uebergang
		@ids = ids
	end
end

class Teilgraph
	# @nodes: list of contained nodes
	# @edges: list of contained edges
	# @ids: hash of {ID => [Elements with this ID]}
	
	attr_accessor :nodes, :edges, :ids
	
	def initialize
		@nodes = []
		@edges = []
		@ids = {}
	end

	def clone
		neu = Teilgraph.new
		neu.nodes = @nodes.clone
		neu.edges = @edges.clone
		@ids.each do |s,w|
			neu.ids[s] = w.clone
		end
		return neu
	end

	def +(other)
		neu = Teilgraph.new
		neu.nodes = (@nodes + other.nodes).uniq
		neu.edges = (@edges + other.edges).uniq
		neu.ids = @ids.merge(other.ids){|s, w1, w2| (w1 + w2).uniq}
		return neu
		end

	def element_zu_id_hinzufuegen(id, element)
		if !@ids[id] then @ids[id] = [] end
		@ids[id].push(element).uniq!
	end

	def to_s
		'Nodes: ' + @nodes.to_s + ', Edges: ' + @edges.to_s + ', IDs: ' + @ids.to_s
	end
	
end

class Hash
	def teilgraph_ausgeben(befehle, datei = :console)
		operationen = befehle.parse_query
		
		# Sortieren
		self[:tg].each do |tg|
			tg.ids.values.each{|arr| arr.sort!{|a,b| a.ID.to_i <=> b.ID.to_i}}
		end
		operationen['sort'].each do |op|
			op[:lambda] = evallambda(op, self[:id_type])
		end
		self[:tg].sort! do |a,b|
			# Hierarchie der sort-Befehle abarbeiten
			vergleich = 0
			operationen['sort'].reject{|op| !op}.each do |op|
				begin
					vergleich = op[:lambda].call(a) <=> op[:lambda].call(b)
				rescue StandardError => e
					raise e.message + " in Zeile:\n" + op[:string]
				end
				if vergleich != 0
					break vergleich
				end
			end
			vergleich
		end
		
		# Ausgabe
		operationen['col'].each{|op| op[:lambda] = evallambda(op, self[:id_type])}
		if datei.class == String or datei == :string
			rueck = CSV.generate(:col_sep => "\t") do |csv|
				csv << ['match_no'] + operationen['col'].map{|o| o[:title]}
				self[:tg].each_with_index do |tg, i|
					csv << [i+1] + operationen['col'].map do |op|
						begin
							op[:lambda].call(tg)
						rescue StandardError => e
							raise e.message + " in Zeile:\n" + op[:string]
							puts tg
							'error!'
						end
					end
				end
			end
			if datei.class == String
				puts 'Schreibe Ausgabe in Datei "' + datei + '.csv".'
				open(datei + '.csv', 'wb') do |file|
					file.write(rueck)
				end
			elsif datei == :string
				return rueck
			end
		elsif datei == :console
			self[:tg].each_with_index do |tg, i|
				operationen['col'].each do |op|
					begin
						puts op[:title] + ': ' + op[:lambda].call(tg).to_s
					rescue StandardError
						raise "Fehler in Zeile:\n" + op[:string]
					end
				end
			end
		end
	end

end

class String
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
end

