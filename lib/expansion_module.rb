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

module Expansion
	require 'yaml'
	
	attr_accessor :expansion_rules

	def initialize
		super
		load_expansion_rules
	end

	def load_expansion_rules(file = nil)
		if !file then file = 'conf/expansion.yml' end
		exp = File::open(file){|yf| YAML::load(yf)}
		exp[:args] = exp[:args].parse_link[:op]
		exp[:co] = exp[:co].parse_link[:op]
		exp[:s] = exp[:s].parse_attributes[:op]
		exp[:rp] = exp[:rp].parse_attributes[:op]
		@expansion_rules = exp
	end

	def praedikationen_einfuehren(sentence = nil)
		satzarray = @nodes.values
		if sentence then satzarray.select!{|k| k.sentence == sentence} end
		satzarray.select!{|k| k.fulfil?(@expansion_rules[:s])}
		satzarray.each do |satz|
			sentence = satz.sentence
			satz.praedikation
			# CO-Kanten berücksichtigen:
			satz.links(@expansion_rules[:co]).each do |knot, tg|
				pfad = tg.edges
				self.add_edge(:type => 'g', :start => satz.praedikation, :end => knot.praedikation, :attr => {'cat'=>'co', 'f-layer'=>'t', 'sentence'=>sentence})
				pfad.last.attr.delete('f-layer')
			end
		end
	end

	def referenten_einfuehren(sentence = nil)
		ausdruckarray = @nodes.values.select{|k| k.fulfil?(@expansion_rules[:rp]) || k.cat == 'P'}
		#ausdruckarray = @nodes.values.select{|k| k.cat == 'RP' || k.cat == 'P' || k.token}
		if sentence then ausdruckarray.select!{|k| k.sentence == sentence} end
		ausdruckarray.each do |ausdruck|
			sentence = ausdruck.sentence
			ausdruck.referent
			# CO-Kanten berücksichtigen:
			ausdruck.links(@expansion_rules[:co]).each do |knot, tg|
				pfad = tg.edges
				if self.edges_between(ausdruck.referent, knot.referent){|e| e.cat == 'co'} == []
					self.add_edge(:type => 'g', :start => ausdruck.referent, :end => knot.referent, :attr => {'cat'=>'co', 'f-layer'=>'t', 'sentence'=>sentence})
				end
				if pfad.last.attr['s-layer'] == 't'
					pfad.last.attr.delete('f-layer')
				end
			end
		end
	end

	def argumente_einfuehren(sentence = nil)
		satzarray = @nodes.values.select{|k| k.fulfil?(@expansion_rules[:s]) or k.cat == 'P'}
		if sentence then satzarray.select!{|k| k.sentence == sentence} end
		satzarray.each do |satz|
			sentence = satz.sentence
			vorhandene_argumente = []
			satz.links(@expansion_rules[:args]).each do |ausdruck, tg|
				pfad = tg.edges
				rolle = pfad[-1].cat
				if ausdruck.cat != 'ARG'
					argument = self.add_node(:attr => {'cat'=>'ARG', 'sentence'=>sentence, 'f-layer'=>'t'})
					self.add_edge(:type => 'g', :start => satz.praedikation, :end => argument, :attr => {'cat'=>rolle, 'f-layer'=>'t', 'sentence'=>sentence})
					self.add_edge(:type => 'g', :start => ausdruck.referent, :end => argument, :attr => {'cat'=>'as', 'f-layer'=>'t', 'sentence'=>sentence})
					# ggf. ARG und Ausdruck verbinden
					if !pfad.map{|k| k.attr['s-layer']}.include?(nil)
						self.add_edge(:type => 'g', :start => argument, :end => ausdruck, :attr => {'cat'=>'ex', 'f-layer'=>'t', 'sentence'=>sentence})
					end
					if pfad.last.attr['s-layer'] == 't'
						pfad.last.attr.delete('f-layer')
						#pfad.last.cat = 'c'
					else
						pfad.last.delete
					end
				end
				vorhandene_argumente << rolle
			end
			# fehlende Argumente ergänzen:
			rollen = @expansion_rules[:valency]
			vorhandene_argumente.reject!{|a| !rollen.flatten.include?(a)}
			rollen.each do |komplett|
				if vorhandene_argumente & komplett != [] and vorhandene_argumente != komplett
					(komplett - vorhandene_argumente).each do |rolle|
						argument = self.add_node(:attr => {'cat'=>'ARG', 'sentence'=>sentence, 'f-layer'=>'t'})
						referent = self.add_node(:attr => {'cat'=>'R', 'sentence'=>sentence, 'f-layer'=>'t'})
						self.add_edge(:type => 'g', :start => satz.praedikation, :end => argument, :attr => {'cat'=>rolle, 'f-layer'=>'t', 'sentence'=>sentence})
						self.add_edge(:type => 'g', :start => referent, :end => argument, :attr => {'cat'=>'as', 'f-layer'=>'t', 'sentence'=>sentence})
					end
				end
			end
		end
	end

	def apply_shortcuts(sentence = nil, file = nil)
		searchgraph = self.clone
		if sentence then searchgraph.filter!('sentence:"'+sentence+'"') end
		@expansion_rules[:shortcuts].each do |sc|
			search = sc[:search]
			exec = sc[:exec].parse_eval
			
			found = searchgraph.teilgraph_suchen(search)
			found[:tg].each do |tg|
				# in exec die IDs auflösen:
				string = exec[:string].clone
				exec[:ids].keys.sort{|a,b| b.begin <=> a.begin}.each do |stelle|
					id = exec[:ids][stelle]
					case found[:id_type][id]
					when 'node'
						string[stelle] = 'tg.ids["' + id + '"][0]'
					when 'nodes', 'text', 'link'
						string[stelle] = 'tg.ids["' + id + '"]'
					end
				end
				lambda = eval('lambda{|tg| ' + string + '}')
				lambda.call(tg)
			end
		end
	end

	def merkmale_projizieren(sentence = nil, file = nil)
		projection_rules = load_projection_rules(file)
		knotenarray = @nodes.values.select{|k| k.fulfil?(projection_rules[:root])}
		if sentence then knotenarray.select!{|k| k.sentence == sentence} end
		knotenarray.each do |knoten|
			knoten.project_features(projection_rules)
		end
	end

	def load_projection_rules(file = nil)
		if !file then file = 'conf/feature_projection.yml' end
		pr = File::open(file){|yf| YAML::load(yf)}
		pr[:root] = pr[:root].to_s.parse_attributes[:op]
		pr[:edges].each do |r|
			r[:edge] = r[:edge].to_s.parse_attributes[:op]
		end
		return pr
	end

	def argumente_entfernen(sentence = nil)
		argumentarray = @nodes.values.select{|k| k.cat == 'ARG'}
		if sentence then argumentarray.select!{|k| k.sentence == sentence} end
		argumentarray.each do |arg|
			sentence = arg.sentence
			praedikation = arg.parent_nodes.select{|k| k.cat == 'P'}[0]
			praedkante = arg.in.select{|k| k.start == praedikation}[0]
			satz = praedikation.satz
			ausdruck = arg.child_nodes{|e| e.cat == 'ex'}[0] or ausdruck = arg.referent.child_nodes{|e| e.cat == 'ex'}
			if ausdruck.class == Array and ausdruck.length == 1 then ausdruck = ausdruck[0] end
			
			if satz
				if ausdruck.class != Array and nachk = satz.nachkommen(nil, 's-ebene:y').select{|n| n['knoten'] == ausdruck}[0]
					nachk['pfad'].last.cat = praedkante.cat
					nachk['pfad'].last.attr['f-layer'] = 't'
				elsif ausdruck.class != Array
					self.add_edge(:type => 'g', :start => satz, :end => ausdruck, :attr => {'cat'=>praedkante.cat, 'f-layer'=>'t', 'sentence'=>sentence})
				else
					self.add_edge(:type => 'g', :start => satz, :end => arg.referent, :attr => {'cat'=>praedkante.cat, 'f-layer'=>'t', 'sentence'=>sentence})
				end
			else # wenn es keinen Satz gibt
				#self.add_edge(:type => 'g', :start => praedikation, :end => arg.referent, :attr => {'cat'=>praedkante.cat, 'f-layer'=>'t', 'sentence'=>sentence})
			end
			praedkante.end = arg.referent
			arg.delete
		end
		# Was soll das hier bedeuten:?
		@edges.each do |i,k|
		end
		@nodes.values.select{|k| ['R', 'P'].include?(k.cat)}.each do |k|
		end
	end

	def referenten_entfernen(sentence = nil)
		referentenarray = @nodes.values.select{|k| k.cat == 'R' || k.cat == 'PR'}
		if sentence then referentenarray.select!{|k| k.sentence == sentence} end
		referentenarray.each do |ref|
			# Ausdrücke semantifizieren
			ref.ausdruecke.each do |aus|
				if !aus.token then aus.attr['f-layer'] = 't' end
			end
			# Über Entfernung entscheiden
			entfernen = true
			praed = ref.reifizierte_praedikation
			if praed && ref.ausdruecke.length == 1
				reco = ref.child_nodes{|e| e.cat == 'co'}
				if reco != []
					praedco = praed.child_nodes{|e| e.cat == 'co'}
					reco.each do |co|
						if !(praedco.include?(co) || praedco.include?(co.reifizierte_praedikation))
							entfernen = false
						end
					end
				end
				umleiten_auf = praed
			elsif ref.ausdruecke.length == 1
				ausdruck = ref.ausdruecke[0]
				if ref.child_nodes{|e| e.cat == 'co'} != []
					ausdrucknachk = ausdruck.nachkommen('co')
					# CO-Kanten semantifizieren
					ausdrucknachk.map{|n| n['pfad']}.each do |pfad|
						pfad.last.attr['f-layer'] = 't'
					end
					ausdruckco = ausdrucknachk.map{|n| n['knoten']}
					ref.child_nodes{|e| e.cat == 'co'}.each do |co|
						if !ausdruckco.include?(co) && !ausdruckco.include?(co.reifizierte_praedikation)
							entfernen = false
						end
					end
				end
				umleiten_auf = ausdruck
			elsif praed and ref.ausdruecke.include?(praed.satz)
				entfernen = false
				ref.out.select{|k| k.end == praed.satz && k.cat == 'ex'}.each{|k| k.delete}
			elsif praed
			else
				entfernen = false
			end
			if entfernen
				ref.in.clone.each do |kante|
					kante.end = umleiten_auf
				end
				ref.delete
			end
		end
	end

	def praedikationen_entfernen(sentence = nil)
		praedarray = @nodes.values.select{|k| k.cat == 'P'}
		if sentence then praedarray.select!{|k| k.sentence == sentence} end
		praedarray.each do |praed|
			entfernen = true
			if praed.satz
				praed.out.reject{|k| k.cat == 'ex'}.each do |kante|
					satznachk = praed.satz.nachkommen(kante.cat)
					if satznachk.map{|n| n['knoten']}.include?(kante.end)
						satznachk.select{|n| n['knoten'] == kante.end}.map{|n| n['pfad']}.each do |pfad|
							pfad.last.attr['f-layer'] = 't'
							kante.delete
						end
					elsif satznachk.map{|n| n['knoten']} & kante.end.ausdruecke != []
						satznachk.select{|n| kante.end.ausdruecke.include?(n['knoten'])}.map{|n| n['pfad']}.each do |pfad|
							pfad.last.attr['f-layer'] = 't'
							kante.delete
						end
					else
						entfernen = false
					end
				end
			else
				entfernen = false
			end
			if entfernen
				# eingehende Kanten auf Satz umleiten
				Array.new(praed.in.reject{|k| k.cat == 'ex'}).each do |kante|
					kante.end = praed.satz
				end
				# ausgehende Kanten auf Satz umleiten
				praed.out.reject{|k| k.cat == 'ex'}.each do |kante|
					kante.start = praed.satz
				end
				praed.satz.attr['f-layer'] = 't'
				praed.delete
			end
		end
	end

	def merkmale_reduzieren(sentence = nil, datei = nil)
		projection_rules = load_projection_rules(datei)
		knotenarray = @nodes.values.select{|k| k.cat == 'RP' or k.cat == 'S'}
		if sentence then knotenarray.select!{|k| k.sentence == sentence} end
		knotenarray.each do |knoten|
			knoten.reduce_features(projection_rules)
		end
	end

	def expandieren(sentence = nil)
		apply_shortcuts(sentence)
		praedikationen_einfuehren(sentence)
		referenten_einfuehren(sentence)
		argumente_einfuehren(sentence)
		merkmale_projizieren(sentence)
	end

	def komprimieren(sentence = nil)
		argumente_entfernen(sentence)
		referenten_entfernen(sentence)
		praedikationen_entfernen(sentence)
		merkmale_reduzieren(sentence)
		# Aufräumen:
		@nodes.values.select{|k| !sentence || k.sentence == sentence}.clone.each do |k|
			k.referent = nil
			k.praedikation = nil
			k.satz = nil
		end
	end


	def add_predication(h)
		args = [*h[:args]]
		anno = h[:anno]
		clause = h[:clause]
		pred = nil
		ns = clause ? clause.sentence : (args ? args[0].sentence : '')
		
		if clause then pred = clause.praedikation end
		if !pred then
			pred = add_node(:attr => {'cat' => 'P', 'f-layer' => 't', 'sentence' => ns})
			if clause then add_edge(:type => 'g', :start => pred, :end => clause, :attr => {'cat' => 'ex', 'f-layer' => 't', 'sentence' => ns}) end
		end
		if anno then pred.attr.update(anno) end
		
		roles = @expansion_rules[:valency][args.length - 1]
		args.each_with_index do |arg, i|
			case arg.cat
				when 'ARG'
					add_edge(:type => 'g', :start => pred, :end => arg, :attr => {'cat' => roles[i], 'sentence' => ns})
				when 'R'
					add_argument(:pred => pred, :ref => arg, :role => roles[i])
				else
					add_argument(:pred => pred, :ref => arg.referent, :role => roles[i], :term => arg)
			end
		end
		
		return pred
	end

	def add_argument(h)
		pred = h[:pred]
		ref = h[:ref]
		role = h[:role]
		term = h[:term]
		arg = nil
		if pred and ref and role
			arg = add_node(:attr => {'cat' => 'ARG', 'f-layer' => 't', 'sentence' => ref.sentence})
			add_edge(:type => 'g', :start => ref, :end => arg, :attr => {'cat' => 'as', 'f-layer' => 't', 'sentence' => ref.sentence})
			add_edge(:type => 'g', :start => pred, :end => arg, :attr => {'cat' => role, 'f-layer' => 't', 'sentence' => pred.sentence})
			if term then add_edge(:type => 'g', :start => arg, :end => term, :attr => {'cat' => 'ex', 'f-layer' => 't', 'sentence' => arg.sentence}) end
		end
		return arg
	end

	def de_sem(elems)
		elems = [*elems]
		elems.each do |elem|
			if elem.attr['s-layer'] == 't'
				elem.attr.delete('f-layer')
			else
				elem.delete
			end
		end
	end

end

class Anno_node

	def referent=(ref)
		@referent = ref
	end

	def referent
		if !@referent
			ns = self.sentence
			if self.cat == 'R'
				@referent = self
			elsif @referent = self.parent_nodes{|e| e.cat == 'ex'}.select{|n| n.cat == 'R'}[0]
			elsif self.fulfil?(@graph.expansion_rules[:rp])
				@referent = @graph.add_node(:attr => {'cat'=>'R', 'f-layer'=>'t', 'sentence'=>ns})
				@graph.add_edge(:type => 'g', :start => @referent, :end => self, :attr => {'cat'=>'ex', 'f-layer'=>'t', 'sentence'=>ns})
			elsif self.cat == 'ARG'
				if not @referent = self.parent_nodes{|e| e.cat == 'as'}[0]
					@referent = @graph.add_node(:attr => {'cat'=>'R', 'f-layer'=>'t', 'sentence'=>ns})
					@graph.add_edge(:type => 'g', :start => @referent, :end => self, :attr => {'cat'=>'as', 'f-layer'=>'t', 'sentence'=>ns})
				end
			elsif self.cat == 'P'
				# neues Modell: P ist schon Ereignisreferent!
				# Problem: Korrelativum!!!
					@referent = self
				#if not @referent = self.in.select{|k| @graph.expansion_rules[:reifications].include?(k.cat)}.map{|k| k.start}[0] # Achtung: was wenn es mehrere Reifikationen gibt????
				#	@referent = @graph.add_node(:attr => {'cat'=>'R', 'f-layer'=>'t', 'sentence'=>ns})
				#	@graph.add_edge(:type => 'g', :start => @referent, :end => self, :attr => {'cat'=>'re', 'f-layer'=>'t', 'sentence'=>ns})
				#	if self.satz && !@referent.child_nodes{|e| e.cat == 'ex'}.include?(self.satz)
				#		@graph.add_edge(:type => 'g', :start => @referent, :end => self.satz, :attr => {'cat'=>'ex', 'f-layer'=>'t', 'sentence'=>ns})
				#	end
				#end
			elsif self.fulfil?(@graph.expansion_rules[:s])
				@referent = self.praedikation.referent
			elsif self.token
				if @eingehende_kanten.map{|k| k.cat} & @graph.expansion_rules[:predications] != [] # oder muß hier noch was bedacht werden? Was ist mit OP?
					@referent = @graph.add_node(:attr => {'cat'=>'PR', 'f-layer'=>'t', 'sentence'=>ns})
					@graph.add_edge(:type => 'g', :start => @referent, :end => self, :attr => {'cat'=>'ex', 'f-layer'=>'t', 'sentence'=>ns})
				end
			else
				@referent = nil
			end
		end
		if @referent and @attr['s-layer'] == 't'
			@attr.delete('f-layer')
		end
		return @referent
	end

	def praedikation=(praed)
		@praedikation = praed
	end

	def praedikation
		if !@praedikation
			ns = self.sentence
			reifizierungen = @graph.expansion_rules[:reifications]
			if self.cat == 'P'
				@praedikation = self
			elsif self.fulfil?(@graph.expansion_rules[:s])
				if referent_ex = self.in.select{|k| k.cat == 'ex' && k.start.cat == 'R'}.map{|kante| {:knoten => kante.start, :kante => kante}}[0]
					referent_ex[:kante].cat = 're'
				end
				reif = self.in.select{|k| reifizierungen.include?(k.cat)}.map{|kante| {:knoten => kante.start, :kante => kante}}
				if @praedikation = self.parent_nodes{|e| e.cat == 'ex'}.select{|n| n.cat == 'P'}[0]
				elsif reif != []
					@praedikation = @graph.add_node(:attr => {'cat'=>'P', 'f-layer'=>'t', 'sentence'=>ns})
					@graph.add_edge(:type => 'g', :start => @praedikation, :end => self, :attr => {'cat'=>'ex', 'f-layer'=>'t', 'sentence'=>ns})
					reif.each do |r|
						@graph.add_edge(:type => 'g', :start => r[:knoten], :end => self, :attr => {'cat'=>'ex', 'f-layer'=>'t', 'sentence'=>ns})
						r[:kante].end = @praedikation
					end
				else
					@praedikation = @graph.add_node(:attr => {'cat'=>'P', 'f-layer'=>'t', 'sentence'=>ns})
					@graph.add_edge(:type => 'g', :start => @praedikation, :end => self, :attr => {'cat'=>'ex', 'f-layer'=>'t', 'sentence'=>ns})
				end
			end
		end
		if @praedikation && @attr['s-layer'] == 't'
			@attr.delete('f-layer')
		end
		return @praedikation
	end

	def satz=(satz)
		@satz = satz
	end

	def satz
		if !@satz
			extoechter = self.child_nodes{|e| e.cat == 'ex'}
			if self.fulfil?(@graph.expansion_rules[:s])
				@satz = self
			elsif self.cat == 'P'
				if extoechter.length == 1
					@satz = extoechter[0]
				end
			elsif self.cat == 'R'
				if self.reifizierte_praedikation(true)
					@satz = self.reifizierte_praedikation(true).satz
				end
			end
		end
		return @satz
	end

	def ausdruecke
		if @attr['s-layer'] == 't'
			ausdruecke = [self]
		else
			case self.cat
			when 'R', 'PR'
				ausdruecke = self.child_nodes{|e| e.cat == 'ex'}
				if self.reifizierte_praedikation(true)
					ausdruecke += self.reifizierte_praedikation(true).ausdruecke
				end
			when 'P'
				ausdruecke = self.child_nodes{|e| e.cat == 'ex'}
			when 'ARG'
				ausdruecke = self.child_nodes{|e| e.cat == 'ex'} + self.referent.ausdruecke
			end
		end
		return ausdruecke.uniq
	end

	def reifizierte_praedikation(ds = false)
		praedikationen = []
		relationen = @expansion_rules[:reifications]
		if ds then relationen += @graph.expansion_rules[:direct_speech] end
		relationen.each do |rel|
			praedikationen += self.child_nodes{|e| e.cat == rel}
		end
		return praedikationen[0]
	end

	def project_features(projection_rules)
		if !@projected_features
			projection_rules[:edges].each do |pr|
				self.out.select{|k| k.fulfil?(pr[:edge])}.each do |kante|
					if pr[:additive]
						features_to_be_projected = kante.end.project_features(projection_rules).select{|s,w| pr[:features].include?(s)}
					else
						features_to_be_projected = kante.end.project_features(projection_rules).reject{|s,w| pr[:features].include?(s)}
					end
					pr[:rules].each do |r|
						if @attr.includes(r[:old]) && features_to_be_projected.includes(r[:new])
							features_to_be_projected.merge!(r[:result])
						end
					end
					@attr.merge!(features_to_be_projected)
				end
			end
			@projected_features = @attr.reject{|s,w| ['cat', 'sentence', 's-layer', 'f-layer', 'token'].include?(s)}
			@unreduced_features = nil
		end
		return @projected_features
	end

	def reduce_features(projection_rules)
		if !@unreduced_features
			@unreduced_features = @attr.reject{|s,w| ['cat', 'sentence', 's-layer', 'f-layer', 'token'].include?(s)}
			projection_rules[:edges].reverse.each do |pr|
				self.out.select{|k| k.fulfil?(pr[:edge])}.each do |kante|
					if pr[:additive]
						features_from_below = kante.end.reduce_features(projection_rules).select{|s,w| pr[:features].include?(s)}
					else
						features_from_below = kante.end.reduce_features(projection_rules).reject{|s,w| pr[:features].include?(s)}
					end
					pr[:rules].each do |r|
						if @attr.includes(r[:result]) && features_from_below.includes(r[:new])
							@attr.delete_if{|s,w| r[:result][s] == w}
							@attr.merge!(r[:old])
						end
					end
					@attr.delete_if{|s,w| features_from_below[s] == w}
				end
			end
			@projected_features = nil
		end
		return @unreduced_features
	end

end

class Anno_graph
	include(Expansion)
end