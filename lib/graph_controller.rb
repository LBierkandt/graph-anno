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

class GraphController
	attr_writer :sinatra
	attr_reader :display, :sentence_list, :graph_file, :search_result

	def initialize
		@graph = AnnoGraph.new
		@display = GraphDisplay.new(@graph)
		@graph_file = ''
		@data_table = nil
		@search_result = ''
		@sentence_list = []
		@sentences_html = ''
	end

	def root
		check_cookies
		@sinatra.haml(
			:index,
			:locals => {
				:controller => self
			}
		)
	end
	
	def set_vars(params, request, response)
		@sinatra.params = params
		@sinatra.request = request
		@sinatra.response = response
	end
	
	def draw_graph
		@display.sentence = @sinatra.request.cookies['traw_sentence']
		satzinfo = @display.draw_graph(:svg, 'public/graph.svg')
		return {:sentence_changed => true}.update(satzinfo).to_json
	end
	
	def toggle_refs
		@display.show_refs = !@display.show_refs
		satzinfo = @display.draw_graph(:svg, 'public/graph.svg')
		return {:sentence_changed => false}.update(satzinfo).to_json
	end
	
	def handle_commandline
		puts 'Processing command: "' + @sinatra.params[:txtcmd] + '"'
		set_cmd_cookies
		if @sinatra.params[:sentence] == ''
			@display.sentence = nil
		else
			@display.sentence = @sinatra.params[:sentence]
		end
		execute_command(@sinatra.params[:txtcmd], @sinatra.params[:layer])
		@sinatra.response.set_cookie('traw_sentence', { :value => @display.sentence })
		satzinfo = @display.draw_graph(:svg, 'public/graph.svg')
		# Prüfen, ob sich Satz geändert hat:
		if @sinatra.request.cookies['traw_sentence'] == @display.sentence
			sentence_changed = false
		else
			sentence_changed = true
		end
		# prüfen, ob sich die Satzliste geändert hat (und nur dann neue Liste fürs select-Feld erstellen)
		if (new_sentence_list = @graph.sentences) != @sentence_list
			@sentence_list = new_sentence_list
			@sentences_html = @display.build_sentence_html(@sentence_list)
		else
			@sentences_html = nil
		end
		return {
			:sentences_html => @sentences_html,
			:sentence_changed => sentence_changed,
			:graph_file => @graph_file
		}.update(satzinfo).to_json
	end
	
	def change_sentence
		set_cmd_cookies
		@display.sentence = @sinatra.params[:sentence]
		satzinfo = @display.draw_graph(:svg, 'public/graph.svg')
		return {:sentence_changed => true}.update(satzinfo).to_json
	end
	
	def filter
		set_filter_cookies
		mode = @sinatra.params[:mode].partition(' ')
		@display.filter = {:cond => @graph.parse_attributes(@sinatra.params[:filter])[:op], :mode => mode[0], :show => (mode[2] == 'rest')}
		@display.sentence = @sinatra.request.cookies['traw_sentence']
		satzinfo = @display.draw_graph(:svg, 'public/graph.svg')
		return {:sentence_changed => false, :filter_applied => true}.update(satzinfo).to_json
	end
	
	def search
		set_query_cookies
		begin
			@display.found = @graph.teilgraph_suchen(@sinatra.params[:query])
			@search_result = @display.found[:tg].length.to_s + ' matches'
		rescue StandardError => e
			@display.found = {:tg => [], :id_type => {}}
			@search_result = '<span class="error_message">' + e.message.gsub("\n", '</br>') + '</span>'
		end
		@display.found[:all_nodes] = @display.found[:tg].map{|tg| tg.nodes}.flatten.uniq
		@display.found[:all_edges] = @display.found[:tg].map{|tg| tg.edges}.flatten.uniq
		@display.found[:sentences] = @display.found[:all_nodes].map{|k| k.sentence}.uniq
		@display.sentence = @sinatra.request.cookies['traw_sentence']
		satzinfo = @display.draw_graph(:svg, 'public/graph.svg')
		puts '"' + @search_result + '"'
		return {
			:sentences_html => @display.build_sentence_html(@sentence_list),
			:search_result => @search_result,
			:sentence_changed => false
		}.update(satzinfo).to_json
	end
	
	def export_subcorpus
		if @display.found
			subgraph = {'nodes' => [], 'edges' => []}
			@display.found[:sentences].each do |sentence|
				subgraph['nodes'] += @graph.nodes.values.select{|k| k.sentence == sentence}
				subgraph['edges'] += @graph.edges.values.select{|k| k.sentence == sentence}
			end
			@sinatra.headers("Content-Type" => "data:Application/octet-stream; charset=utf8")
			return JSON.pretty_generate(subgraph, :indent => ' ', :space => '').encode('UTF-8')
		end
	end
	
	def export_data
		if @display.found
			begin
				anfrage = @sinatra.params[:query]
				@data_table = teilgraph_ausgeben(@display.found, anfrage, :string)
				return ''
			rescue StandardError => e
				return e.message
			end
		end
	end
	
	def export_data_table
		if @data_table
			@sinatra.headers("Content-Type" => "data:Application/octet-stream; charset=utf8")
			return @data_table
		end
	end


	def execute_command(command_line, layer)
		command_line.strip!
		command = command_line.partition(' ')[0]
		string = command_line.partition(' ')[2]
		parameters = string.parse_parameters
		properties = @display.layer_attributes[layer].to_h
	
		case command
			when 'n' # new node
				if @display.sentence
					layer = set_new_layer(parameters[:words], properties)
					properties['sentence'] = @display.sentence
					properties.merge!(parameters[:attributes])
					@graph.add_node(:attr => properties)
				end
			
			when 'e' # new edge
				if @display.sentence
					layer = set_new_layer(parameters[:words], properties)
					properties['sentence'] = @display.sentence
					properties.merge!(parameters[:attributes])
					@graph.add_edge(
						:type => 'g',
						:start => element_by_identifier(parameters[:all_nodes][0]),
						:end => element_by_identifier(parameters[:all_nodes][1]),
						:attr => properties
					)
				end
			
			when 'a' # annotate elements
				if @display.sentence
					@display.layers.map{|l| l['attr']}.each do |a|
						properties.delete(a)
					end
					
					properties.merge!(parameters[:attributes])
					
					parameters[:elements].each do |element_id|
						if element = element_by_identifier(element_id)
							element.attr.merge!(properties)
							parameters[:keys].each{|k| element.attr.delete(k)}
						end
					end
				end
			
			when 'd' # delete elements
				if @display.sentence
					(parameters[:meta] + parameters[:nodes] + parameters[:edges]).each do |el|
						if element = element_by_identifier(el)
							element.delete
						end
					end
					parameters[:tokens].each do |token|
						if element = element_by_identifier(token)
							element.remove_token
						end
					end
				end
			
			when 'l' # set layer
				layer = set_new_layer(parameters[:words], properties)
	
			when 'p', 'g' # group under new parent node
				if @display.sentence
					layer = set_new_layer(parameters[:words], properties)
					properties['sentence'] = @display.sentence
					mother = @graph.add_node(:attr => properties.merge(parameters[:attributes]))
					(parameters[:nodes] + parameters[:tokens]).each do |node|
						if element = element_by_identifier(node)
							@graph.add_edge(
								:type => 'g',
								:start => mother,
								:end => element,
								:attr => properties.clone
							)
						end
					end
				end
			
			when 'c', 'h' # attach new child node
				if @display.sentence
					layer = set_new_layer(parameters[:words], properties)
					properties['sentence'] = @display.sentence
					daughter = @graph.add_node(:attr => properties.merge(parameters[:attributes]))
					(parameters[:nodes] + parameters[:tokens]).each do |node|
						if element = element_by_identifier(node)
							@graph.add_edge(
								:type => 'g',
								:start => element,
								:end => daughter,
								:attr => properties.clone
							)
						end
					end
				end
	
			when 'ns' # create new sentence
				metaknoten = @graph.nodes.values.select{|k| k.cat == 'meta'}
				
				parameters[:words].each do |ns|
					if metaknoten.select{|k| k.sentence == ns}.empty?
						@graph.add_node(:attr => {'cat' => 'meta', 'sentence' => ns})
					end
				end
				
				@display.sentence = parameters[:words][0]
	
			when 't' # build tokens and append them
				if @display.sentence
					@graph.build_tokens(parameters[:words], @display.sentence)
				end
				
			when 'ti' # build tokens and insert them 
				if @display.sentence
					knoten = element_by_identifier(parameters[:tokens][0])
					@graph.build_tokens(parameters[:words][1..-1], @display.sentence, knoten)
				end
				
			when 's' # change sentence
				@display.sentence = parameters[:words][0]
	
			when 'del' # delete sentence
				if @display.sentence
					saetze = @graph.sentences
					index = saetze.index(@display.sentence) + 1
					if index == saetze.length then index -= 2 end
					
					@graph.nodes.values.select{|k| k.sentence == @display.sentence}.each{|k| k.delete}
					@graph.edges.values.select{|k| k.sentence == @display.sentence}.each{|k| k.delete}
					
					# change to next sentence
					@display.sentence = saetze[index]
				end
	
			when 'load', 'laden' # clear workspace and load corpus file
				@graph_file.replace('data/' + parameters[:words][0] + '.json')
				
				@graph.read_json_file(@graph_file)
				saetze = @graph.sentences
				if not saetze.include?(@display.sentence)
					@display.sentence = saetze[0]
				end
			
			when 'add' # load corpus file and add it to the workspace
				@graph_file.replace('')
				addgraph = AnnoGraph.new
				addgraph.read_json_file('data/' + parameters[:words][0] + '.json')
				@graph.update(addgraph)
			
			when 'save', 'speichern' # save workspace to corpus file
				if parameters[:words][0] then @graph_file.replace(@graph_file.replace('data/' + parameters[:words][0] + '.json')) end
				if !File.exist?('data') then Dir.mkdir('data') end
				if @display.sentence
					@graph.write_json_file(@graph_file)
				end
			
			when 'clear', 'leeren' # clear workspace
				@graph_file.replace('')
				@graph.clear
				@display.sentence = nil
	
			when 'image' # export sentence as graphics file
				if @display.sentence
					format = parameters[:words][0]
					name = parameters[:words][1]
					if !File.exist?('images') then Dir.mkdir('images') end
					@display.draw_graph(format.to_sym, 'images/'+name+'.'+format)
				end
			
			when 'export' # export corpus in other format
				format = parameters[:words][0]
				name = parameters[:words][1]
				name2 = parameters[:words][2]
				case format
					when 'paula'
						require_relative 'paula_exporter'
						@graph.export_paula(name, name2 ? name2 : nil)
					when 'salt'
						require_relative 'salt_exporter'
						@graph.export_saltxml(name)
				end
	
			when 'import_toolbox' # import Toolbox data
				@graph_file.replace('')
				@graph.clear
				require_relative 'toolbox_module'
				datei = parameters[:words][0]
				formatbeschreibung = string.sub(datei, '').strip.sub(/^""/, '')
				puts formatbeschreibung
				begin
					# Ruby format: allows simple qoutes
					format = instance_eval(formatbeschreibung)
				rescue
					# for hash: ":" instead of "=>"
					format = JSON.parse(formatbeschreibung)
				end
				@graph.toolbox_einlesen(datei, format)
	
			# all following commands are related to annotation @graph expansion -- Experimental!
			when 'project'
				@graph.merkmale_projizieren(@display.sentence)
			when 'reduce'
				@graph.merkmale_reduzieren(@display.sentence)
	
			when 'adv'
				nodes = (parameters[:all_nodes]).map{|n| element_by_identifier(n)}
				@graph.add_predication(:args=>nodes[0..-2], :anno=>{'sem'=>'caus'}, :clause=>nodes[-1])
			when 'ref'
				(parameters[:nodes] + parameters[:tokens]).each{|n| element_by_identifier(n).referent}
			when 'pred'
				(parameters[:nodes] + parameters[:tokens]).each{|n| element_by_identifier(n).praedikation}
			when 'desem'
				@graph.de_sem(parameters[:elements].map{|n| element_by_identifier(n)})
			when 'sc'
				@graph.apply_shortcuts(@display.sentence)
			
			
			when 'exp'
				@graph.expandieren(@display.sentence)
			when 'exp1'
				@graph.praedikationen_einfuehren(@display.sentence)
			when 'exp3'
				@graph.referenten_einfuehren(@display.sentence)
			when 'exp4'
				@graph.argumente_einfuehren(@display.sentence)
			when 'expe'
				@graph.apply_shortcuts(@display.sentence)
				@graph.praedikationen_einfuehren(@display.sentence)
				@graph.referenten_einfuehren(@display.sentence)
				@graph.argumente_einfuehren(@display.sentence)
				@graph.argumente_entfernen(@display.sentence)	
				@graph.merkmale_projizieren(@display.sentence)
			when 'exp-praed'
				#@graph.praedikationen_einfuehren(@display.sentence)
				@graph.praedikationen_einfuehren(@display.sentence)
				@graph.referenten_einfuehren(@display.sentence)
				@graph.argumente_einfuehren(@display.sentence)
				@graph.argumente_entfernen(@display.sentence)
				@graph.referenten_entfernen(@display.sentence)
				# Aufräumen:
				@graph.nodes.values.select{|k| @display.sentence == nil || k.sentence == @display.sentence}.clone.each do |k|
					k.referent = nil
					k.praedikation = nil
					k.satz = nil
					k.gesammelte_merkmale = nil
					k.unreduzierte_merkmale = nil
				end
			when 'exp-ref'
				@graph.komprimieren(@display.sentence)
				@graph.praedikationen_einfuehren(@display.sentence)
				@graph.referenten_einfuehren(@display.sentence)
				@graph.argumente_einfuehren(@display.sentence)
				@graph.argumente_entfernen(@display.sentence)
				# Aufräumen:
				@graph.nodes.values.select{|k| @display.sentence == nil || k.sentence == @display.sentence}.clone.each do |k|
					k.referent = nil
					k.praedikation = nil
					k.satz = nil
					k.gesammelte_merkmale = nil
					k.unreduzierte_merkmale = nil
				end
			when 'exp-arg'
				@graph.komprimieren(@display.sentence)
				@graph.expandieren(@display.sentence)
				# Aufräumen:
				@graph.nodes.values.select{|k| @display.sentence == nil || k.sentence == @display.sentence}.clone.each do |k|
					k.referent = nil
					k.praedikation = nil
					k.satz = nil
					k.gesammelte_merkmale = nil
					k.unreduzierte_merkmale = nil
				end
	
			when 'komp'
				@graph.komprimieren(@display.sentence)
			when 'komp-arg'
				@graph.argumente_entfernen(@display.sentence)
			when 'komp-ref'
				@graph.referenten_entfernen(@display.sentence)
			when 'komp-praed'
				@graph.komprimieren(@display.sentence)
				#@graph.praedikationen_entfernen(@display.sentence)
				#@graph.adverbialpraedikationen_entfernen(@display.sentence)
				## Aufräumen:
				#@graph.nodes.values.select{|k| @display.sentence == nil || k.sentence == @display.sentence}.clone.each do |k|
				#	k.referent = nil
				#	k.praedikation = nil
				#	k.satz = nil
				#	k.gesammelte_merkmale = nil
				#	k.unreduzierte_merkmale = nil
				#end
	
		end
	end

	def element_by_identifier(identifier)
		i = identifier.scan(/\d/).join.to_i
		case identifier[0]
			when 'm'
				return @display.meta
			when 'n'
				return @display.nodes[i]
			when 'e'
				return @display.edges[i]
			when 't'
				return @display.tokens[i]
			else
				return nil
		end
	end
	
	def check_cookies
		if @sinatra.request.cookies['traw_sentence'].nil?
			@sinatra.response.set_cookie('traw_sentence', { :value => '' })
		end
	
		if @sinatra.request.cookies['traw_layer'].nil?
			@sinatra.response.set_cookie('traw_layer', { :value => 'fs_layer' })
		end
	
		if @sinatra.request.cookies['traw_cmd'].nil?
			@sinatra.response.set_cookie('traw_cmd', { :value => '' })
		end
	
		if @sinatra.request.cookies['traw_query'].nil?
			@sinatra.response.set_cookie('traw_query', { :value => '' })
		end
	end
	
	def set_cmd_cookies
		if @sinatra.request.cookies['traw_layer'] && @sinatra.params[:layer]
			@sinatra.response.set_cookie('traw_layer', { :value => @sinatra.params[:layer] })
		end
	
		if @sinatra.request.cookies['traw_cmd'] && @sinatra.params[:txtcmd]
			@sinatra.response.set_cookie('traw_cmd', { :value => @sinatra.params[:txtcmd] })
		end
	
		if @sinatra.request.cookies['traw_sentence'] && @sinatra.params[:sentence]
			@sinatra.response.set_cookie('traw_sentence', { :value => @sinatra.params[:sentence] })
		end
	end
	
	def set_filter_cookies
		#if @sinatra.request.cookies['traw_filter']
			@sinatra.response.set_cookie('traw_filter', { :value => @sinatra.params[:filter] })
		#end
		#if @sinatra.request.cookies['traw_filter_mode']
			@sinatra.response.set_cookie('traw_filter_mode', { :value => @sinatra.params[:mode] })
		#end
	end
	
	def set_query_cookies
		if @sinatra.request.cookies['traw_query']
			@sinatra.response.set_cookie('traw_query', { :value => @sinatra.params[:query] })
		end
	end
	
	def set_new_layer(words, properties)
		if new_layer_shortcut = words.select{|w| @display.layer_shortcuts.keys.include?(w)}.last
			layer = @display.layer_shortcuts[new_layer_shortcut]
			@sinatra.response.set_cookie('traw_layer', { :value => layer })
			properties.replace(@display.layer_attributes[layer].to_h)
			return layer
		end
	end

end

class String
	def parse_parameters
		str = self.strip
		h = {
			:attributes => {},
			:keys => [],
			:elements => [],
			:words => [],
			:all_nodes => [],
			:meta => [],
			:nodes => [],
			:edges => [],
			:tokens => []
		}
		
		r = {}
		r[:ctrl] = '(\s|:)'
		r[:bstring] = '[^\s:"]+'
		#r[:qstring] = '"(([^"]*(\\\"[^"]*)*[^\\\])|)"'
		r[:qstring] = '"([^"]*(\\\"[^"]*)*([^"\\\]|\\\"))?"'
		r[:string] = '(' + r[:qstring] + '|' + r[:bstring] + ')'
		r[:attribute] = r[:string] + ':' + r[:string] + '?'
		r.keys.each{|k| r[k] = Regexp.new('^' + r[k])}
		
		while str != ''
			m = nil
			if m = str.match(r[:ctrl])
			elsif m = str.match(r[:attribute])
				key = m[2] ? m[2].gsub('\"', '"') : m[1]
				val = m[6] ? m[6].gsub('\"', '"') : m[5]
				if val == nil
					h[:keys] << key
				else
					h[:attributes][key] = val
				end
			elsif m = str.match(r[:string])
				word = m[2] ? m[2].gsub('\"', '"') : m[1]
				h[:words] << word
				if word.match(/^(([ent]\d+)|m)$/)
					h[:elements] << word
					case word[0]
						when 'm'
							h[:meta] << word
						when 'n'
							h[:nodes] << word
							h[:all_nodes] << word
						when 't'
							h[:tokens] << word
							h[:all_nodes] << word
						when 'e'
							h[:edges] << word
					end
				elsif mm = word.match(/^([ent])(\d+)\.\.\1(\d+)$/)
					([mm[2].to_i, mm[3].to_i].min..[mm[2].to_i, mm[3].to_i].max).each do |n|
						h[:elements] << mm[1] + n.to_s
						case word[0]
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
				end
			else
				break
			end
			str = str[m[0].length..-1]
		end
		
		return h
	end
end
