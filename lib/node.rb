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

class Node < NodeOrEdge
	attr_accessor :id, :in, :out, :start, :end

	# initializes node
	# @param h [{:graph => Graph, :id => String, :attr => Hash}]
	def initialize(h)
		@graph = h[:graph]
		@id = h[:id]
		@in = []
		@out = []
		@type = h[:type]
		@attr = Attributes.new(h.merge(:host => self))
		@start= h[:start]
		@end  = h[:end]
		@custom = h[:custom]
		@graph.node_index[@type][@id] = self
	end

	def inspect
		"Node#{@id}"
	end

	# @return [Hash] the node transformed into a hash
	def to_h
		h = {
			:id     => @id,
			:type   => @type,
			:start  => @start,
			:end    => @end,
			:custom => @custom,
		}.merge(@attr.to_h).compact
	end

	# deletes self and all in- and outgoing edges; optionally writes changes to log
	# @param log_step [Step] optionally a log step to which the changes will be logged
	# @return [Node] self
	def delete(log_step = nil)
		if log_step
			@out.each{|e| log_step.add_change(:action => :delete, :element => e)}
			@in.each{|e| log_step.add_change(:action => :delete, :element => e)}
			log_step.add_change(:action => :delete, :element => self)
		end
		Array.new(@out).each(&:delete)
		Array.new(@in).each(&:delete)
		@graph.node_index[@type].delete(@id)
		@graph.nodes.delete(@id)
	end

	# returns nodes connected to self by ingoing edges which fulfil the (optional) block
	# @param &block [Proc] only edges for which &block evaluates to true are taken into account; if no block is given, alls edges are considered
	# @return [Array] list of found parent nodes
	def parent_nodes(&block)
		selected = @in.select(&block)
		selected = @in if selected.is_a?(Enumerator)
		return selected.map(&:start)
	end

	# returns nodes connected to self by outgoing edges which fulfil the (optional) block
	# @param &block [Proc] only edges for which &block evaluates to true are taken into account; if no block is given, alls edges are considered
	# @return [Array] child nodes connected by edges with the defined attributes
	def child_nodes(&block)
		selected = @out.select(&block)
		selected = @out if selected.is_a?(Enumerator)
		return selected.map(&:end)
	end

	# returns all token nodes that are dominated by self, or connected to self via the given link (in their linear order)
	# @param link [String] a query language string describing the link from self to the tokens that will be returned
	# @return [Array] all dominated tokens or all tokens connected via given link
	def tokens(link = nil)
		case @type
		when 'a'
			self.nodes((link || 'edge+'), 'token').sort_by(&:tokenid)
		when 't'
			[self]
		when 's'
			sentence_tokens
		when 'p'
			sentence_nodes.map(&:tokens).flatten
		end
	end

	# like tokens method, but returns text string represented by tokens
	# @param link [String] a query language string describing the link from self to the tokens whose text will be returned
	# @return [String] the text formed by all dominated tokens or all tokens connected via given link
	def text(link = nil)
		self.tokens(link).map(&:token) * ' '
	end

	# @return [Node] the sentence node self is associated with
	def sentence
		if @type == 's'
			self
		elsif @type == 'p'
			nil
		else
			parent_nodes{|e| e.type == 's'}[0]
		end
	end

	# @return [Array] the sentence nodes self dominates
	def sentence_nodes
		if @type == 'p'
			nodes = [self]
			loop do
				children = nodes.map{|n| n.child_sections}.flatten
				return @graph.sentence_nodes & nodes if children.empty? # use "&"" to preserve sentence order
				nodes = children
			end
		elsif @type == 's'
			[self]
		else
			[]
		end
	end

	# @return [Array] the tokens of the sentence self belongs to
	def sentence_tokens
		s = sentence
		if @type == 't'
			ordered_sister_nodes{|t| t.sentence === s}
		elsif @type == 's'
			if first_token = child_nodes{|e| e.type == 's'}.of_type('t')[0]
				if first_token.speaker
					child_nodes{|e| e.type == 's'}.of_type('t').sort{|a, b| a.start <=> b.start}
				else
					first_token.ordered_sister_nodes{|t| t.sentence === s}
				end
			else
				[]
			end
		elsif @type == 'p'
			sentence_nodes.map(&:sentence_tokens).flatten
		else
			s.sentence_tokens
		end
	end

	def speaker
		if @type == 'sp'
			self
		else
			parent_nodes{|e| e.type == 'sp'}[0]
		end
	end

	# @param block [Lambda] a block to filter the considered sister nodes
	# @return [Array] an ordered list of the sister nodes of self, optionally filtered by a block
	def ordered_sister_nodes(&block)
		block ||= lambda{|n| true}
		nodes = [self]
		node = self
		while node = node.node_before(&block)
			nodes.unshift(node)
		end
		node = self
		while node = node.node_after(&block)
			nodes.push(node)
		end
		return nodes
	end

	# @return [String] the text of the sentence self belongs to
	def sentence_text
		sentence_tokens.map(&:token) * ' '
	end

	# @return [Float] the position of self in terms of own tokenid or averaged tokenid of the dominated (via tokens method) tokens
	# @param link [String] a query language string describing the link from self to the tokens that will be returned
	def position(link = nil)
		if @type == 't'
			return self.tokenid.to_f
		else
			toks = self.tokens(link)
			return toks.length > 0 ? toks.reduce(0){|sum, t| sum += t.position} / toks.length : 0
		end
	end

	def position_wrt(other, stil = nil, detail = true)
		st = self.tokens
		ot = other.tokens
		r = ''
		if st == [] || ot == [] || self.sentence != other.sentence
			return 'nd'
		end
		if st & ot != []
			if st == ot
				return 'idem'
			elsif ot - st == []
				if stil == 'eq' then return 'super' elsif stil == 'dom' then else r = 'super_' end
				st = st - ot
			elsif st - ot == []
				if stil == 'eq' then return 'sub' elsif stil == 'dom' then else r = 'sub_' end
				ot = ot - st
			else
				return 'intersect'
			end
		end
		st_first = st.first.tokenid
		st_last  = st.last.tokenid
		ot_first = ot.first.tokenid
		ot_last  = ot.last.tokenid
		if st_last < ot_first
			r += 'pre'
			r += '_separated' if detail and st_last < ot_first - 1
		elsif st_first > ot_last
			r +='post'
			r += '_separated' if detail and st_first > ot_last + 1
		elsif st_first > ot_first && st_last < ot_last &&
			ot.any?{|t| t.tokenid < st_first || t.tokenid > st_last}
			r += 'in'
		elsif st_first < ot_first && st_last > ot_last &&
			st.any?{|t| t.tokenid < ot_first || t.tokenid > ot_last}
			r += 'circum'
		else
			r += 'interlaced'
			if detail
				if    st_first < ot_first && st_last < ot_last
					r += '_pre'
				elsif st_first > ot_first && st_last > ot_last
					r += '_post'
				elsif st_first > ot_first && st_last < ot_last
					r += '_in'
				elsif st_first < ot_first && st_last > ot_last
					r += '_circum'
				end
			end
		end
		return r
	end

	# returns the node preceding self if self is ordered via order edges, else nil
	# @param block [Lambda] a block to filter the considered nodes
	# @return [Node] the preceding node
	def node_before(&block)
		block ||= lambda{|n| true}
		parent_nodes{|e| e.type == 'o'}.select(&block)[0]
	end

	# returns the node following self if self is ordered via order edges, else nil
	# @param block [Lambda] a block to filter the considered nodes
	# @return [Node] the following node
	def node_after(&block)
		block ||= lambda{|n| true}
		child_nodes{|e| e.type == 'o'}.select(&block)[0]
	end

	# returns a list of the nodes that are connected to self via links that match a given structure
	# @param pfad_oder_automat [String, Automat] a query language string or automat the link has to match
	# @param zielknotenbedingung [String, Hash] optional; a condition the target node has to match (query language string or condition hash)
	# @return [Array] a list of arrays that contain the found target node and a Teilgraph comprising the connection
	def links(pfad_oder_automat, zielknotenbedingung = nil)
		if pfad_oder_automat.is_a?(String)
			automat = Automat.create(@graph.parse_link(pfad_oder_automat)[:op])
			automat.bereinigen
		elsif pfad_oder_automat.is_a?(Automat)
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
							neuer_tg = z[:tg].clone
							neuer_tg.edges << z[:el]
							if z[:forward] # nur Forwärtskanten sollen implizit gefunden werden
								neue_zustaende += automat.schrittliste_graph(z.merge(:el => z[:el].end, :tg => neuer_tg))
							end
						else # wenn keine zielknotenbedingung dann war der letzte gefundene Knoten schon das Ziel
							letzer_knoten = z[:forward] ? z[:el].start : z[:el].end
							rueck << [letzer_knoten, z[:tg]]
						end
					end
				else # wenn z[:zustand] != nil
					neue_zustaende += automat.schrittliste_graph(z.merge(:tg => z[:tg].clone))
				end
			end
			if neue_zustaende == []
				return rueck.uniq
			end
		end
	end

	# @param link [String] a link in query language
	# @param end_node_condition [String] an attribute description in query language to filter the returned nodes
	# @return [Array] when no link is given: the nodes associated with the sentence node self; when link is given: the nodes connected to self via given link
	def nodes(link = nil, end_node_condition = '')
		if link
			links(link, @graph.parse_attributes(end_node_condition)[:op]).map{|node_and_link| node_and_link[0]}.uniq
		else
			if @type == 'p' || @type == 's'
				sentence_nodes.map{|s| s.child_nodes{|e| e.type == 's'}}.flatten
			else
				sentence.nodes
			end
		end
	end

	# methods specific for token nodes:

	# @return [String] self's text
	def token
		@attr['token']
	end

	# @param arg [String] new self's text
	def token=(arg)
		@attr['token'] = arg
	end

	# @return [Integer] position of self in ordered list of own sentence's tokens
	def tokenid
		self.sentence_tokens.index(self)
	end

	# deletes self and joins adjacent tokens if possible
	# @param log_step [Step] optionally a log step to which the changes will be logged
	def remove_token(log_step = nil)
		if self.token
			s = self.sentence
			if self.node_before && self.node_after
				e = @graph.add_order_edge(:start => self.node_before, :end => self.node_after)
				log_step.add_change(:action => :create, :element => e) if log_step
			end
			self.delete(log_step)
		end
	end

	# methods specific for section nodes:

	# @return [String] self's name attribute
	def name
		@attr['name']
	end

	# @param name [String] self's new name attribute
	def name=(name)
		@attr['name'] = name
	end

	# the level of a section node: sentence nodes have level 0, parents of sentence nodes level 1 etc.
	# @return [Integer] the level
	def sectioning_level
		if @type == 's'
			0
		elsif @type == 'p'
			child_sections.map(&:sectioning_level).max + 1
		else
			nil
		end
	end

	# @return [Array] the descendant sections of self
	def descendant_sections
		if sectioning_level > 0
			child_sections + child_sections.map(&:descendant_sections).flatten
		else
			[]
		end
	end

	# @return [Array] the ancestor sections nodes of self, from bottom to top
	def ancestor_sections
		ancestors = []
		current_node = self
		loop do
			if p = current_node.parent_section
				ancestors << current_node = p
			else
				return ancestors
			end
		end
	end

	# @return [Array] self's annotations including annotations inherited from its ancestor nodes
	def inherited_attributes
		current_attr = Attributes.new(:host => self)
		ancestor_sections.reverse.each do |ancestor|
			current_attr = current_attr.full_merge(ancestor.attr)
		end
		current_attr.full_merge(attr)
	end

	# @return [Array] an ordered list of the sections that are on the same level as self
	def same_level_sections
		@graph.section_structure_nodes[sectioning_level]
	end

	# return true if the sentences self contains are before and after the sentences the other section contains;
	# in this case, the other section has to be dominated by self
	# @param other [Node] the other section
	# @return [Boolean] whether the other section's sentences are comprised
	def comprise_section?(other)
		all_sentence_nodes = @graph.sentence_nodes
		return all_sentence_nodes.index(sentence_nodes.first) < all_sentence_nodes.index(other.sentence_nodes.first) &&
			all_sentence_nodes.index(sentence_nodes.last) > all_sentence_nodes.index(other.sentence_nodes.last)
	end

	# @return [Node] the parent section if present, else nil
	def parent_section
		parent_nodes{|e| e.type == 'p'}[0]
	end

	# @return [Array] the child sections
	def child_sections
		child_nodes{|e| e.type == 'p'}
	end
end
