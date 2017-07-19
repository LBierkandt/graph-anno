# encoding: utf-8

# Copyright © 2014-2017 Lennart Bierkandt <post@lennartbierkandt.de>
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

class Automat
	attr_accessor :zustaende

	def self.create(operation, ids = [])
		ids = ids.clone
		ids << operation[:id] if operation[:id]
		case operation[:operator]
		when 'node', 'edge', 'redge'
			return Automat.new(Zustand.new(operation[:operator].to_sym, nil, operation[:cond], ids))
		when 'boundary'
			return Automat.new(Zustand.new(:node, nil, Graph.new.parse_attributes('cat:"boundary" & level:'+operation[:level])[:op]))
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
					elsif zz.folgezustand.is_a?(Array)
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
			elsif forward # wenn das aktuelle Element eine Kante ist;  nur Forwärtskanten sollen implizit gefunden werden
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
			nk.out.of_type('a').each do |auskante|
				liste << {:zustand => naechster_zustand, :tg => tg, :el => auskante, :forward => true}
			end
			nk.in.of_type('a').each do |einkante|
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
		@nodes.reject!{|n| n.type == 't' && n.cat == 'boundary'}
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
