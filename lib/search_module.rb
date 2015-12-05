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

require 'unicode_utils/downcase.rb'
require 'csv.rb'
require_relative 'parser_module.rb'

module SearchableGraph
	include Parser

	def initialize
		super
		@makros = []
	end

	def teilgraph_suchen(query)
		operations = parse_query(query)

		puts 'Searching for graph fragment ...'
		startzeit = Time.new

		suchgraph = self.clone
		tglisten = {}
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

		# check validity of query
		if (error_messages = query_errors(operations)) != []
			raise error_messages * "\n"
		end

		# edge in link umwandeln, wenn Start und Ziel gegeben
		convert_edge_clauses(operations)

		# meta
		# hier wird ggf. der zu durchsuchende Graph eingeschränkt
		if metabedingung = operation_erzeugen(:op => 'and', :arg => operations['meta'].map{|op| op[:cond]})
			metaknoten = sentence_nodes.select{|s| s.fulfil?(metabedingung)}
			suchgraph.nodes.values.select!{|n| metaknoten.include?(n.sentence)}
			suchgraph.edges.values.select!{|e| metaknoten.include?(e.start.sentence) || metaknoten.include?(e.end.sentence)}
		end

		# edge
		operations['edge'].each do |operation|
			gefundene_kanten = suchgraph.edges.values.select{|k| k.fulfil?(operation[:cond])}
			tglisten[tgindex += 1] = gefundene_kanten.map do |k|
				Teilgraph.new([], [k], {operation[:id] => [k]})
			end
			id_index[operation[:id]] = {:index => tgindex, :art => operation[:operator], :cond => operation[:cond]}
		end

		# node/nodes
		# gefundene Knoten werden als atomare Teilgraphen gesammelt
		(operations['node'] + operations['nodes']).each do |operation|
			gefundene_knoten = suchgraph.nodes.values.select{|k| k.type != 's' && k.fulfil?(operation[:cond])}
			tglisten[tgindex += 1] = gefundene_knoten.map do |k|
				Teilgraph.new([k], [], {operation[:id] => [k]})
			end
			if operation[:operator] == 'nodes'
				tglisten[tgindex] << Teilgraph.new([], [], {operation[:id] => []})
			end
			id_index[operation[:id]] = {:index => tgindex, :art => operation[:operator], :cond => operation[:cond]}
		end

		# text
		# ein oder mehrer Teilgraphenlisten werden erstellt
		operations['text'].each do |operation|
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
		operations['link'].sort{|a,b| link_operation_vergleichen(a, b, id_index)}.each_with_index do |operation, operation_index|
			startid = operation[:start]
			zielid = operation[:end]
			next unless id_index[startid] && id_index[zielid]
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
							if startknot
								breitensuche = startknot.links(automat, id_index[zielid][:cond])
							else
								breitensuche = []
							end
							breitensuche = [[nil, Teilgraph.new]] if breitensuche == []
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
							if startknot
								breitensuche = startknot.links(automat, {:operator => 'token'}) # Zielknoten muß Token sein
							else
								breitensuche = []
							end
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
			# link-ids in id_index
			operation[:ids].each do |id|
				id_index[id] = {:index => tgindex, :art => operation[:operator]}
			end
			# id_index auffrischen
			id_index.each do |id,tgi|
				id_index[id][:index] = tgindex if tgi[:index] == startindex || tgi[:index] == zielindex
			end
			# Operation löschen
			operations['link'].delete_at(operation_index)
		end

		# Teilgraphen zusammenfassen, und zwar dann, wenn sie alle ihre "node"-Knoten bzw. "text"e teilen
		if operations['nodes'] != []
			node_indizes = id_index.select{|s,w| w[:art] == 'node' || w[:art] == 'text'}
			# für jede TG-Liste, die "node"s oder "text"e enthält:
			node_indizes.values.map{|h| h[:index]}.uniq.each do |node_tgindex|
				node_ids = node_indizes.select{|s,w| w[:index] == node_tgindex}.keys
				zusammengefasste_tg = {}
				tglisten[node_tgindex].each do |referenztg|
					# "node"s/"text"e des Referenz-TG
					uebereinstimmend = referenztg.ids.select{|s,w| node_ids.include?(s)}.values.map{|k| k.sort_by{|n| n.id.to_i}}
					# in Hash unter "uebereinstimmend"en Knoten zusammenfassen
					if zusammengefasste_tg[uebereinstimmend]
						zusammengefasste_tg[uebereinstimmend] += referenztg
					else
						zusammengefasste_tg[uebereinstimmend] = referenztg
					end
				end
				# alte tg-Liste löschen
				tglisten.delete(node_tgindex)
				# neue einfügen
				tglisten[tgindex += 1] = zusammengefasste_tg.values
				# id_index auffrischen
				id_index.each do |id,tgi|
					id_index[id] = tgindex if tgi == node_tgindex
				end
			end
		end

		tgliste = tglisten.values.flatten(1)
		tgliste.each{|tg| tg.set_ids(id_index)}

		# cond
		operations['cond'].each do |op|
			begin
				tgliste.select!{|tg| tg.execute(op[:string])}
			rescue NoMethodError => e
				match = e.message.match(/undefined method `(\w+)' for .+:(\w+)/)
				raise "Undefined method '#{match[1]}' for #{match[2]} in line:\ncond #{op[:string]}"
			rescue StandardError => e
				raise "#{e.message} in line:\ncond #{op[:string]}"
			rescue SyntaxError => e
				raise clean_syntax_error_message(:message => e.message, :line => "cond #{op[:string]}")
			end
		end

		puts "Found #{tgliste.length.to_s} matches in #{(Time.new - startzeit).to_s} seconds"
		puts

		return tgliste
	end

	def query_errors(operations)
		text_ids = operations['text'].map{|o| ([o[:id]] + o[:ids]).flatten.compact}
		node_ids = operations['node'].map{|o| o[:id]}
		nodes_ids = operations['nodes'].map{|o| o[:id]}
		edge_start_end_ids = operations['edge'].map{|o| [o[:start], o[:end]]}
		link_start_end_ids = operations['link'].map{|o| [o[:start], o[:end]]}
		edge_ids = operations['edge'].map{|o| o[:id]}
		link_ids = operations['link'].map{|o| o[:ids]}.flatten
		anno_ids = @@annotation_commands.map{|c| operations[c].map{|o| o[:ids]}}.flatten.uniq
		# at least one node, edge or text clause
		if operations['node'] + operations['edge'].select{|o| !(o[:start] or o[:end])} + operations['text'] == []
			return ['A query must contain at least one node clause, edge clause or text clause.']
		end
		# check for multiply defined ids
		error_messages = []
		all_ids = (text_ids + node_ids + nodes_ids + edge_ids + link_ids).flatten.compact
		all_ids.select{|id| all_ids.count(id) > 1}.uniq.each do |id|
			error_messages << "The id #{id} is multiply defined."
		end
		# references to undefined ids?
		erlaubte_start_end_ids = node_ids + nodes_ids + text_ids.flatten
		benutzte_start_end_ids = (edge_start_end_ids + link_start_end_ids).flatten.compact
		als_referenz_erlaubte_ids = erlaubte_start_end_ids + edge_ids + link_ids
		benutzte_start_end_ids.each do |id|
			error_messages << "The id #{id} is used as start or end, but is not defined." unless erlaubte_start_end_ids.include?(id)
		end
		['cond', 'sort', 'col'].each do |op_type|
			operations[op_type].map{|o| o[:ids]}.flatten.each do |id|
				unless als_referenz_erlaubte_ids.include?(id)
					error_messages << "The id #{id} is used in #{op_type} clause, but is not defined."
				end
			end
		end
		if (undefined_ids = anno_ids - als_referenz_erlaubte_ids) != []
			if undefined_ids.length == 1
				error_messages << "The id #{undefined_ids[0]} is used in annotation command, but is not defined."
			else
				error_messages << "The ids #{undefined_ids * ', '} are used in annotation command, but are not defined."
			end
		end
		# check for dangling edges
		if erlaubte_start_end_ids.length > 0 and operations['edge'].any?{|o| !(o[:start] && o[:end])} or
			erlaubte_start_end_ids.length == 0 and operations['edge'].length > 1
			error_messages << 'There are dangling edges.'
		end
		# coherent graph fragment?
		groups = text_ids + (node_ids + nodes_ids).map{|id| [id]}
		links = edge_start_end_ids + link_start_end_ids
		unless groups.groups_linked?(links)
			error_messages << 'The defined graph fragment is not coherent.'
		end
		return error_messages
	end

	def convert_edge_clauses(operations)
		operations['edge'].clone.each do |operation|
			if operation[:start] and operation[:end]
				operations['link'] << {
					:operator => 'edge',
					:start => operation[:start],
					:end   => operation[:end],
					:arg   => operation.reject{|s,w| [:start, :end].include?(s)},
					:ids   => [operation[:id]].compact
				}
				operations['edge'].delete(operation)
			end
		end
	end

	def textsuche_NFA(operation, id = nil)
		automat = Automat.create(operation)
		automat.bereinigen

		# Grenzknoten einbauen (das muß natürlich bei einem Graph mit verbundenen Sätzen und mehreren Ebenen anders aussehen)
		grenzknoten = []
		@nodes.values.select{|k| k.token}.each do |tok|
			if !tok.node_before
				grenzknoten << self.add_token_node(:attr => {'token' => '', 'cat' => 'boundary', 'level' => 's'})
				self.add_order_edge(:start => grenzknoten.last, :end => tok)
			end
			if !tok.node_after
				grenzknoten << self.add_token_node(:attr => {'token' => '', 'cat' => 'boundary', 'level' => 's'})
				self.add_order_edge(:start => tok, :end => grenzknoten.last)
			end
		end

		ergebnis = []
		@nodes.values.select{|k| k.token}.each do |node|
			if t = automat.text_suchen_ab(node)
				t.remove_boundary_nodes!
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

	def teilgraph_ausgeben(found, befehle, datei = :console)
		operations = parse_query(befehle)

		# Sortieren
		found[:tg].each do |tg|
			tg.ids.values.each{|arr| arr.sort_by!{|n| n.id.to_i}}
		end
		found[:tg].sort! do |a,b|
			# Hierarchie der sort-Befehle abarbeiten
			vergleich = 0
			operations['sort'].reject{|op| !op}.each do |op|
				begin
					vergleich = a.execute(op[:string]) <=> b.execute(op[:string])
				rescue NoMethodError => e
					match = e.message.match(/undefined method `(\w+)' for .+:(\w+)/)
					raise "Undefined method '#{match[1]}' for #{match[2]} in line:\nsort #{op[:string]}"
				rescue StandardError => e
					raise "#{e.message} in line:\nsort #{op[:string]}"
				rescue SyntaxError => e
					raise clean_syntax_error_message(:message => e.message, :line => "sort #{op[:string]}")
				end
				break vergleich if vergleich != 0
			end
			vergleich
		end

		# Ausgabe
		if datei.class == String or datei == :string
			rueck = CSV.generate(:col_sep => "\t") do |csv|
				csv << ['match_no'] + operations['col'].map{|o| o[:title]}
				found[:tg].each_with_index do |tg, i|
					csv << [i+1] + operations['col'].map do |op|
						begin
							tg.execute(op[:string])
						rescue NoMethodError => e
							match = e.message.match(/undefined method `(\w+)' for .+:(\w+)/)
							raise "Undefined method '#{match[1]}' for #{match[2]} in line:\ncol #{op[:title]} #{op[:string]}"
						rescue StandardError => e
							raise "#{e.message} in line:\ncol #{op[:title]} #{op[:string]}"
						rescue SyntaxError => e
							raise clean_syntax_error_message(:message => e.message, :line => "col #{op[:title]} #{op[:string]}")
						end
					end
				end
			end
			if datei.class == String
				puts 'Writing output to file "' + datei + '.csv".'
				open(datei + '.csv', 'wb') do |file|
					file.write(rueck)
				end
			elsif datei == :string
				return rueck
			end
		elsif datei == :console
			found[:tg].each_with_index do |tg, i|
				puts "match #{i}"
				operations['col'].each do |op|
					begin
						puts "#{op[:title]}: #{tg.execute(op[:string])}"
					rescue StandardError => e
						raise "#{e.message} in line:\ncol #{op[:title]} #{op[:string]}"
					end
				end
				puts
			end
		end
	end

	def teilgraph_annotieren(found, command_string)
		search_result_preserved = true
		commands = parse_query(command_string)[:all].select{|c| @@annotation_commands.include?(c[:operator])}
		found[:tg].each do |tg|
			layer = nil
			commands.each do |command|
				# set attributes (same for all commands)
				attrs = interpolate(command[:attributes], tg)
				attrs = allowed_attributes(attrs)
				# set layer (same for all commands)
				if layer_shortcut = command[:words].select{|l| conf.layer_shortcuts.keys.include?(l)}.last
					layer = conf.layer_shortcuts[layer_shortcut]
				end
				# extend attributes accordingly (same for all commands)
				attrs.merge!(conf.layer_attributes[layer]) if layer
				# process the commands
				case command[:operator]
				when 'a'
					elements = command[:ids].map{|id| tg.ids[id]}.flatten.uniq.compact
					elements.each do |el|
						el.annotate(attrs)
					end
				when 'n'
					nodes = command[:ids].map{|id| tg.ids[id]}.flatten.uniq.select{|e| e.is_a?(Node)}
					unless nodes.empty?
						add_anno_node(
							:attr => attrs,
							:sentence => nodes.map{|n| n.sentence}.most_frequent
						)
					end
				when 'e'
					start_nodes = *tg.ids[command[:ids][0]]
					end_nodes   = *tg.ids[command[:ids][1]]
					start_nodes.select!{|e| e.is_a?(Node)}
					end_nodes.select!{|e| e.is_a?(Node)}
					start_nodes.product(end_nodes).each do |start_node, end_node|
						add_anno_edge(
							:start => start_node,
							:end => end_node,
							:attr => attrs
						)
					end
				when 'p', 'g'
					nodes = command[:ids].map{|id| tg.ids[id]}.flatten.uniq.select{|e| e.is_a?(Node)}
					unless nodes.empty?
						add_parent_node(
							nodes,
							attrs,
							conf.layer_attributes[layer],
							nodes.map{|n| n.sentence}.most_frequent
						)
					end
				when 'c', 'h'
					nodes = command[:ids].map{|id| tg.ids[id]}.flatten.uniq.select{|e| e.is_a?(Node)}
					unless nodes.empty?
						add_child_node(
							nodes,
							attrs,
							conf.layer_attributes[layer],
							nodes.map{|n| n.sentence}.most_frequent
						)
					end
				when 'd'
					elements = command[:ids].map{|id| tg.ids[id]}.flatten.uniq.compact
					elements.each do |el|
						el.type == 't' ? el.remove_token : el.delete if el
						search_result_preserved = false
					end
				when 'ni'
					edges = command[:ids].map{|id| tg.ids[id]}.flatten.uniq.select{|e| e.is_a?(Edge)}
					edges.each do |e|
						insert_node(e, attrs)
						search_result_preserved = false
					end
				when 'di', 'do'
					nodes = command[:ids].map{|id| tg.ids[id]}.flatten.uniq.select{|e| e.is_a?(Node)}
					nodes.each do |n|
						delete_and_join(n, command[:operator] == 'di' ? :in : :out)
						search_result_preserved = false
					end
				when 'tb', 'ti'
					nodes = command[:ids].map{|id| tg.ids[id]}.flatten.uniq.compact
					node = nodes.select{|e| e.is_a?(Node) && e.type == 't'}.first
					build_tokens(command[:words][1..-1], :next_token => node)
				when 'ta'
					nodes = command[:ids].map{|id| tg.ids[id]}.flatten.uniq.compact
					node = nodes.select{|e| e.is_a?(Node) && e.type == 't'}.last
					build_tokens(command[:words][1..-1], :last_token => node)
				when 'l'
				end
			end #command
		end # tg
		return search_result_preserved
	end

	def interpolate(attributes, tg)
		attributes.map_hash do |k, v|
			begin
				v ? tg.execute("\"#{v}\"") : nil
			rescue NoMethodError => e
				match = e.message.match(/undefined method `(\w+)' for .+:(\w+)/)
				raise "Undefined method '#{match[1]}' for #{match[2]} in string:\n\"#{v}\""
			rescue StandardError => e
				raise "#{e.message} in string:\n\"#{v}\""
			rescue SyntaxError => e
				raise clean_syntax_error_message(:message => e.message)
			end
		end
	end

	def clean_syntax_error_message(h)
		if h[:line]
			h[:message].sub(/^\(eval\):1: (.+)\n.+\n.*\^.*$/, "\\1 in line:\n#{h[:line]}")
		else
			h[:message].sub(/^\(eval\):1: (.+)\n(.+)\n.*\^.*$/, "\\1 in string:\n\\2")
		end
	end
end

class NodeOrEdge
	def fulfil?(bedingung)
		bedingung = @graph.parse_attributes(bedingung)[:op] if bedingung.class == String
		return true unless bedingung
		satzzeichen = '.,;:?!"'
		case bedingung[:operator]
		when 'attr'
			knotenwert = @attr[bedingung[:key]]
			return false unless knotenwert
			wert = bedingung[:value]
			return true unless wert
			case bedingung[:method]
			when 'plain'
				return true if knotenwert == wert
			when 'insens'
				if bedingung[:key] == 'token'
					return true if UnicodeUtils.downcase(knotenwert.xstrip(satzzeichen)) == UnicodeUtils.downcase(wert)
				else
					return true if UnicodeUtils.downcase(knotenwert) == UnicodeUtils.downcase(wert)
				end
			when 'regex'
				return true if knotenwert.match(wert)
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
			if self.is_a?(Node)
				return @in.select{|k| k.fulfil?(bedingung[:cond])}.length
			else
				return 1
			end
		when 'out'
			if self.is_a?(Node)
				return @out.select{|k| k.fulfil?(bedingung[:cond])}.length
			else
				return 1
			end
		when 'link'
			if self.is_a?(Node)
				return self.links(bedingung[:arg]).length
			else
				return 1
			end
		when 'token'
			if self.is_a?(Node)
				return @type == 't'
			else
				return false
			end
		when 'start'
			if self.is_a?(Edge) && !@start.fulfil?(bedingung[:cond])
				return false
			else
				return true
			end
		when 'end'
			if self.is_a?(Edge) && !@end.fulfil?(bedingung[:cond])
				return false
			else
				return true
			end
		else
			return true
		end
	end
end

class Node < NodeOrEdge
	def links(pfad_oder_automat, zielknotenbedingung = nil)
		if pfad_oder_automat.class == String
			automat = Automat.create(@graph.parse_link(pfad_oder_automat)[:op])
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
				return rueck.uniq
			end
		end
	end

	def nodes(link, zielknotenbedingung = '')
		links(link, @graph.parse_attributes(zielknotenbedingung)[:op]).map{|node_and_link| node_and_link[0]}.uniq
	end
end

class Automat
	attr_accessor :zustaende

	def self.create(operation, ids = [])
		ids = ids.clone
		ids << operation[:id] if operation[:id]
		case operation[:operator]
		when 'node', 'edge', 'redge'
			return Automat.new(Zustand.new(operation[:operator].to_sym, nil, operation[:cond], ids))
		when 'boundary'
			return Automat.new(Zustand.new(:node, nil, SearchableGraph.new.parse_attributes('cat:"boundary" & level:'+operation[:level])[:op]))
		when 'or'
			folgeautomaten = [Automat.create(operation[:arg][0], ids), Automat.create(operation[:arg][1], ids)]
			automat = Automat.new(Zustand.new(:split, [], ids))
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
			automat = Automat.new(Zustand.new(:empty, nil, ids))
			(1..operation[:min]).each do |i|
				automat.automaten_anhaengen(Automat.create(operation[:arg], ids))
			end
			if operation[:max] > operation[:min]
				splitautomat = nil
				(1..operation[:max] - operation[:min]).each do |i|
					splitautomat = Automat.new(Zustand.new(:split, [], ids))
					anhangautomat = Automat.create(operation[:arg], ids)
					leerautomat = Automat.new(Zustand.new(:empty, nil, ids))

					splitautomat.anhaengen(leerautomat)
					splitautomat.anhaengen(anhangautomat)

					splitautomat.startzustand.folgezustand << leerautomat.startzustand
					splitautomat.startzustand.folgezustand << anhangautomat.startzustand

					automat.automaten_anhaengen(splitautomat)
				end
			elsif operation[:max] < 0
				splitautomat = Automat.new(Zustand.new(:split, [], ids))

				leerautomat = Automat.new(Zustand.new(:empty, nil, ids))
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
		@zustaende[0]
	end

	def automaten_anhaengen(neuer_automat)
		@zustaende.each do |z|
			z.folgezustand = neuer_automat.startzustand if z.folgezustand == nil
		end
		self.anhaengen(neuer_automat)
	end

	def anhaengen(neuer_automat)
		@zustaende += neuer_automat.zustaende
	end

	def bereinigen
		@zustaende = @zustaende.uniq
		@zustaende.clone.each do |z|
			if z.typ == :empty
				@zustaende.each_with_index do |zz,i|
					if zz.folgezustand == z
						@zustaende[i].folgezustand = z.folgezustand
					elsif zz.folgezustand.class == Array
						zz.folgezustand.each_with_index do |fz,ii|
							@zustaende[i].folgezustand[ii] = z.folgezustand if fz == z
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
				return z[:tg] if z[:zustand] == nil
				# sonst nächsten Schritt
				neue_zustaende += schrittliste_text(z[:zustand], z[:tg], neuer_knoten)
			end
			return nil if neue_zustaende == []

			# Weiter vorrücken im Text
			neuer_knoten = neuer_knoten.node_after
		end
	end

	def schrittliste_text(z, tg, nk)
		# Liste von Folgezuständen erstellen
		return [{:zustand => nil, :tg => tg}] if z == nil
		liste = []
		case z.typ
		when :split
			liste += schrittliste_text(z.folgezustand[0], tg.clone, nk)
			liste += schrittliste_text(z.folgezustand[1], tg.clone, nk)
		when :empty
			liste += schrittliste_text(z.folgezustand, tg, nk)
		when :node
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
		return [h] if z == nil
		liste = []
		case z.typ
		when :split
			liste += schrittliste_graph(:zustand=>z.folgezustand[0], :tg=>tg.clone, :el=>nk, :forward=>forward)
			liste += schrittliste_graph(:zustand=>z.folgezustand[1], :tg=>tg.clone, :el=>nk, :forward=>forward)
		when :empty
			liste += schrittliste_graph(:zustand=>z.folgezustand, :tg=>tg, :el=>nk, :forward=>forward)
		when :node
			if nk.kind_of?(Node)
				schritt_in_liste(h.clone, liste) if nk.fulfil?(z.uebergang)
			elsif forward # wenn das aktuelle Element eine Kante ist
				schritt_in_liste(h.clone, liste, false)
			end
		when :edge
			if nk.is_a?(Edge)
				schritt_in_liste(h.clone, liste) if forward and nk.fulfil?(z.uebergang)
			else # wenn das aktuelle Element ein Knoten ist
				schritt_in_liste(h.clone, liste, false)
			end
		when :redge
			if nk.is_a?(Edge)
				schritt_in_liste(h.clone, liste) if !forward and nk.fulfil?(z.uebergang)
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
		return if tg.nodes.include?(nk) # zirkuläre Pfade werden ausgeschlossen
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
			nk.out.select{|k| k.type == 'a'}.each do |auskante|
				liste << {:zustand => naechster_zustand, :tg => tg, :el => auskante, :forward => true}
			end
			nk.in.select{|k| k.type == 'a'}.each do |einkante|
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
	# @ids: hash of {id => [Elements with this id]}
	# @id_mapping: an object containing ids set to the respective elements

	attr_accessor :nodes, :edges, :ids

	def initialize(nodes = [], edges = [], ids = {})
		@nodes = nodes
		@edges = edges
		@ids = ids
		@id_mapping = Object.new
	end

	def clone
		Teilgraph.new(@nodes.clone, @edges.clone, @ids.map_hash{|k, v| v.clone})
	end

	def +(other)
		Teilgraph.new(
			(@nodes + other.nodes).uniq,
			(@edges + other.edges).uniq,
			@ids.merge(other.ids){|s, w1, w2| (w1 + w2).uniq}
		)
	end

	def element_zu_id_hinzufuegen(id, element)
		@ids[id] = [] unless @ids[id]
		@ids[id].push(element).uniq!
	end

	def remove_boundary_nodes!
		@nodes.reject!{|n| n.cat == 'boundary' and n.token == ''}
	end

	def to_s
		'Nodes: ' + @nodes.to_s + ', Edges: ' + @edges.to_s + ', ids: ' + @ids.to_s
	end

	def set_ids(id_index)
		id_index.keys.compact.each do |id|
			case id_index[id][:art]
			when 'node', 'edge'
				@id_mapping.instance_variable_set(id, @ids[id][0])
			when 'nodes', 'text', 'link'
				@id_mapping.instance_variable_set(id, @ids[id])
			end
		end
	end

	def execute(code)
		@id_mapping.instance_eval(code)
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

class Array
	def groups_linked?(links)
		return true if self.length == 1
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

	def most_frequent
		group_by{|i| i}.values.max{|x, y| x.length <=> y.length}[0]
	end
end
