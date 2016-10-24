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

class Graph
	def toolbox_einlesen(file, korpusformat)
		# korpusformat:
		# [[marker_0, ..., marker_n], ..., [marker_0, ..., marker_p]]
		# Marker für Tokentext: * voranstellen; Tokeneben wird dadurch ebenfalls festgelegt
		# falls nicht markiert wird ein Defaultwert verwendet (erster Marker der zweituntersten Ebene / Ebene unter Satz)

		@recmarker = korpusformat[0][0]
		# default-Werte für Wort- und Tokenebene
		if korpusformat.length <= 2
			@tokenebene = korpusformat.length - 1
			@textmarker = korpusformat[-1][0]
		else
			@tokenebene = korpusformat.length - 2
			@textmarker = korpusformat[-2][0]
		end
		# Wort- und Tokenebene herausfinden
		korpusformat.each_with_index do |markers, ebene|
			markers.each_with_index do |marker,i|
				if marker[0] == '*'
					korpusformat[ebene][i] = marker[1..-1]
					@textmarker = marker[1..-1]
					@tokenebene = ebene
				end
			end
		end

		puts 'record id marker: ' + @recmarker
		puts 'token layer: ' + @tokenebene.to_s
		puts 'text marker: ' + @textmarker
		puts "reading #{file[:name]}"

		# zusätzliche Variablen zur Formatbeschreibung generieren
		@korpusformat = korpusformat
		@untermarker = []
		korpusformat.length.times do |ebene|
			@untermarker[ebene] = korpusformat[ebene..-1].flatten
		end

		##### Einlesen
		datei = open(file[:tempfile], 'r:iso-8859-1')
		dateitext = datei.readlines * ''
		datei.close

		dateitext.gsub!(/\n([^\\])/, ' \1') # Zeilen zusammenfügen, wenn die folgende nicht mit einem Marker beginnt
		zeilen = dateitext.split("\n")
		korpus = []

		##### recordweise parsen
		recordzeilen = []
		zeilen.each do |zeile|
			# Wenn Record-Anfangsmarker erreicht ist
			if zeile.getmarker == @korpusformat[0][0]
				# Wenn schon Zeilen da
				if recordzeilen != []
					korpus << self.recordparsen(recordzeilen)
				end
				recordzeilen = [zeile]
			# Falls anderer (im Korpusformat deklarierter) Marker auftritt
			elsif @untermarker[0].include?(zeile.getmarker)
				recordzeilen << zeile
			end
		end
		korpus << self.recordparsen(recordzeilen)

		# Nur zu Anschauungs- und Testzwecken:
		#datei = open('tbtest.json', 'w')
		#datei.write(JSON.pretty_generate(korpus))
		#datei.close

		##### Korpus in Graph umwandeln
		letztes_token = nil
		satzknoten = []
		self.baumlesen(0, korpus, nil, -1, letztes_token, nil, satzknoten)
		# Kodierung prüfen
		@nodes.values.each do |n|
			n.attr.each do |k, v|
				puts "Encoding error in record \"#{n.sentence.name}\"" if v.sanitize
			end
		end
	end

	def baumlesen(ebene, korpusteil, mutter, satznr, letztes_token, sentence = nil, satzknoten)
		korpusteil.each do |element|
			if ebene == 0 # Wenn Satzebene:
				type = 's'
				satznr += 1
				sentence_name = element[@recmarker]
				letztes_token = nil
			elsif ebene == @tokenebene
				type = 't'
				element['token'] = element[@textmarker]
				element.delete(@textmarker)
			else
				type = 'a'
				element['s-layer'] = 't'
				element['f-layer'] = 't'
			end
			if type == 's'
				neuer_knoten = add_sect_node(:attr => element.reject{|s,w| s == 'toechter'}, :name => sentence_name)
				add_order_edge(:start => satzknoten.last, :end => neuer_knoten)
				satzknoten << neuer_knoten
			end
			if ebene == @tokenebene
				add_order_edge(:start => letztes_token, :end => neuer_knoten) if letztes_token
				letztes_token = neuer_knoten
			end
			# Kanten erstellen
			if mutter != nil and ebene > 1
				kantenattribute = {}
				kantenattribute['s-layer'] = 't'
				kantenattribute['f-layer'] = 't'
				self.add_anno_edge(:start => mutter, :end => neuer_knoten, :attr => kantenattribute)
			end
			if element['toechter']
				if ebene != @tokenebene
					baumlesen(ebene+1, element['toechter'], neuer_knoten, satznr, letztes_token, sentence, satzknoten)
				else
					# Subtoken: Verketten
					element['toechter'].each do |tochter|
						tochter.each do |s,w|
							if neuer_knoten[s] == nil
								neuer_knoten[s] = w
							else
								neuer_knoten[s] += w
							end
						end
					end
				end
			end
		end
	end

	def inbaum(ebene, start, ende, recordzeilen, schnitte)
		rueck = []
		letzterschnitt = start
		if schnitte[ebene]
			schnittliste = schnitte[ebene].sort
		else
			schnittliste = []
		end
		# Elementgrenzen durchgehen
		schnittliste.each do |schnitt|
			next if schnitt <= start || schnitt > ende
			rueck << {}
			@korpusformat[ebene].each do |marker|
				if recordzeilen[marker]
					rueck.last[marker] = recordzeilen[marker][letzterschnitt..schnitt].strip.force_encoding('utf-8')
				end
			end
			# wenn noch eine tiefere Ebene vorhanden
			if ebene < @korpusformat.length-1
				rueck.last['toechter'] = inbaum(ebene+1, letzterschnitt, schnitt, recordzeilen, schnitte)
			end
			letzterschnitt = schnitt + 1
		end
		return rueck
	end

	def recordparsen(quellzeilen)
		recordzeilen = {}
		record = {}
		# Zeilen des Records verarbeiten
		quellzeilen.each do |zeile|
			# Falls Marker auf Recordebene: Zeile in Record übernehmen
			if @korpusformat[0].include?(zeile.getmarker)
				record[zeile.getmarker] = zeile.without_marker.force_encoding('utf-8')
				puts "Encoding error in record \"#{record[@recmarker]}\"" if record[zeile.getmarker].sanitize
				record[zeile.getmarker].gsub!(/\s+/, ' ')
			# sonst Zeilen mit gleichem Marker konkatenieren ('\n' als Trennzeichen)
			else
				if recordzeilen[zeile.getmarker] == nil
					recordzeilen[zeile.getmarker] = zeile.without_marker + "\n"
				else
					recordzeilen[zeile.getmarker] += zeile.without_marker + "\n"
				end
			end
		end
		# Leerzeichen zwischen konkatenierten Zeilen auffüllen (ersetze '\n')
		schleifenende = false
		loop do
			laenge = {}
			@untermarker[1].each do |marker|
				if recordzeilen[marker]
					if recordzeilen[marker].index("\n") == nil
						# wenn kein \n mehr da: abbrechen
						schleifenende = true
						break
					else
						laenge[marker] = recordzeilen[marker].index("\n")
					end
				end
			end
			break if schleifenende
			break if @untermarker[1].all?{|m| !recordzeilen[m]}
			maxlaenge = laenge.values.max
			@untermarker[1].each do |marker|
				if recordzeilen[marker]
					recordzeilen[marker].sub!("\n", ' ' * (maxlaenge - laenge[marker] + 1))
				end
			end
		end
		# Für jede Ebene Trennstellen (schnitte) zwischen Elementen finden
		leerzeichen = {}
		schnitte = []
		@untermarker[1].each do |marker|
			if recordzeilen[marker]
				positionen = []
				recordzeilen[marker].scan(/ \S/){|x| positionen << $`.size}
				leerzeichen[marker] = (positionen + [recordzeilen[marker].length-1]).uniq
			end
		end
		(1..@korpusformat.length-1).each do |ebene|
			schnitte[ebene] = leerzeichen[@korpusformat[ebene][0]]
			@untermarker[ebene].each do |marker|
				if leerzeichen[marker]
					schnitte[ebene] = schnitte[ebene] & leerzeichen[marker]
				end
			end
		end
		# in Baumstruktur bringen
		recordzeilen[@korpusformat[1][0]] = '' if !recordzeilen[@korpusformat[1][0]]
		record['toechter'] = inbaum(1, 0, recordzeilen[@korpusformat[1][0]].length, recordzeilen, schnitte)
		return record
	end
end
