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

require 'yaml'
require 'graphviz'
	require 'open3'
require 'htmlentities'

class GraphController
	attr_writer :sinatra
	attr_reader :graph, :sentence_list, :graph_file, :search_result

	def initialize
		@graph = AnnoGraph.new
		@graph_file = ''
		@data_table = nil
		@search_result = ''
		@sentence_list = {}
		@sentence = nil
		@sentence = nil
		@tokens = []
		@nodes = []
		@edges = []
		@show_refs = true
		@found = nil
		@filter = {:mode => 'unfilter'}
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

	def draw_graph
		@sentence = @graph.nodes[@sinatra.request.cookies['traw_sentence']]
		satzinfo = generate_graph(:svg, 'public/graph.svg')
		set_sentence_list
		return {:sentence_changed => true, :sentence_list => @sentence_list.values}.merge(satzinfo).to_json
	end

	def toggle_refs
		@show_refs = !@show_refs
		satzinfo = generate_graph(:svg, 'public/graph.svg')
		return {:sentence_changed => false}.merge(satzinfo).to_json
	end

	def layer_options
		@sinatra.haml(
			:layer_options,
			:locals => {
				:controller => self
			}
		)
	end

	def handle_commandline
		puts 'Processing command: "' + @sinatra.params[:txtcmd] + '"'
		set_cmd_cookies
		@sentence = @sinatra.params[:sentence] == '' ? nil : @graph.nodes[@sinatra.params[:sentence]]
		value = execute_command(@sinatra.params[:txtcmd], @sinatra.params[:layer])
		return value.to_json if value
		@sinatra.response.set_cookie('traw_sentence', { :value => @sentence ? @sentence.id : nil })
		satzinfo = generate_graph(:svg, 'public/graph.svg')
		# Prüfen, ob sich Satz geändert hat:
		sentence_changed = (@sentence && @sinatra.request.cookies['traw_sentence'] == @sentence.id) ? false : true
		set_sentence_list
		return {
			:sentence_list => @sentence_list.values,
			:sentence_changed => sentence_changed,
			:graph_file => @graph_file
		}.merge(satzinfo).to_json
	end

	def change_sentence
		set_cmd_cookies
		@sentence = @graph.nodes[@sinatra.params[:sentence]]
		satzinfo = generate_graph(:svg, 'public/graph.svg')
		return {:sentence_changed => true}.merge(satzinfo).to_json
	end

	def set_sentence_list(h = {})
		@sentence_list = Hash[@graph.sentence_nodes.map{|s| [s.id, {:id => s.id, :name => s.name, :found => false}]}]
		if !h[:clear] and @found
			@found[:all_nodes].map{|n| n.sentence.id}.uniq.each do |s|
				@sentence_list[s][:found] = true
			end
		end
	end

	def filter
		set_filter_cookies
		mode = @sinatra.params[:mode].partition(' ')
		@filter = {:cond => @graph.parse_attributes(@sinatra.params[:filter])[:op], :mode => mode[0], :show => (mode[2] == 'rest')}
		@sentence = @graph.nodes[@sinatra.request.cookies['traw_sentence']]
		satzinfo = generate_graph(:svg, 'public/graph.svg')
		return {:sentence_changed => false, :filter_applied => true}.merge(satzinfo).to_json
	end

	def search
		set_query_cookies
		begin
			@found = @graph.teilgraph_suchen(@sinatra.params[:query])
			@search_result = @found[:tg].length.to_s + ' matches'
		rescue StandardError => e
			@found = {:tg => [], :id_type => {}}
			@search_result = '<span class="error_message">' + e.message.gsub("\n", '</br>') + '</span>'
		end
		@found[:all_nodes] = @found[:tg].map{|tg| tg.nodes}.flatten.uniq
		@found[:all_edges] = @found[:tg].map{|tg| tg.edges}.flatten.uniq
		@sentence_list.each{|id, h| h[:found] = false}
		@found[:all_nodes].map{|n| n.sentence.id}.uniq.each do |s|
			@sentence_list[s][:found] = true
		end
		@sentence = @graph.nodes[@sinatra.request.cookies['traw_sentence']]
		satzinfo = generate_graph(:svg, 'public/graph.svg')
		puts '"' + @search_result + '"'
		return {
			:sentence_list => @sentence_list.values,
			:search_result => @search_result,
			:sentence_changed => false
		}.merge(satzinfo).to_json
	end

	def config_form
		@sinatra.haml(
			:config_form,
			:locals => {
				:graph => @graph
			}
		)
	end

	def save_config
		if (result = validate_config(@sinatra.params)) == true
			@sinatra.params['layers'] = @sinatra.params['layers'] || {}
			@sinatra.params['combinations'] = @sinatra.params['combinations'] || {}
			@graph.conf = AnnoGraphConf.new(
				@sinatra.params['general'].inject({}) do |h, (k, v)|
					k == 'edge_weight' ? h[k] = v.to_i : h[k] = v
					h
				end
			)
			@graph.conf.layers = @sinatra.params['layers'].values.map do |layer|
				AnnoLayer.new(layer.map_hash{|k, v| k == 'weight' ? v.to_i : v})
			end
			@graph.conf.combinations = @sinatra.params['combinations'].values.map do |combination|
				combination['attr'] = combination['attr'] || {}
				AnnoLayer.new(
					combination.map_hash do |k, v|
						if k == 'weight'
							v.to_i
						elsif k == 'attr'
							v.values
						else
							v
						end
					end
				)
			end
			@graph.makros_plain = @sinatra.params['makros'].split("\n").map{|s| s.strip}
			@graph.makros += @graph.parse_query(@graph.makros_plain * "\n")['def']
		end
		return result.to_json
	end

	def new_layer(i)
		@sinatra.haml(
			:layer_form_segment,
			:locals => {
				:layer => AnnoLayer.new,
				:i => i
			}
		)
	end

	def new_combination(i)
		@sinatra.haml(
			:combination_form_segment,
			:locals => {
				:combination => AnnoLayer.new(:attr => [], :graph => @graph),
				:i => i,
				:layers => @graph.conf.layers
			}
		)
	end

	def import_form(type)
		modal = "import_form_#{type}".to_sym
		@sinatra.haml(
			modal,
			:locals => {
				:nlp => NLP
			}
		)
	end

	def import(type)
		@graph_file.replace('')
		@graph.clear
		case type
		when 'text'
			case @sinatra.params['input_method']
			when 'file'
				text = @sinatra.params['file'][:tempfile].read.force_encoding('utf-8')
			when 'paste'
				text = @sinatra.params['paste'].gsub("\r\n", "\n").gsub("\r", "\n")
			end
			case @sinatra.params['processing_method']
			when 'regex'
				options = @sinatra.params.select{|k, v| ['processing_method', 'tokens', 'sentences'].include?(k)}
				options['sentences']['sep'].de_escape!
				options['tokens']['regex'] = Regexp.new(options['tokens']['regex'])
			when 'punkt'
				options = @sinatra.params.select{|k, v| ['processing_method', 'language'].include?(k)}
			end
			@graph.import_text(text, options)
		when 'toolbox'
			file = @sinatra.params['file']
			format_description = @sinatra.params['format_description']
			puts 'format description:'
			puts format_description
			format = JSON.parse(format_description)
			@graph.toolbox_einlesen(file, format)
		end
		set_sentence_list(:clear => true)
		@sentence = @graph.nodes[sentence_list.keys.first]
		@sinatra.response.set_cookie('traw_sentence', { :value => @sentence.id, :path => '/' })
		return {:sentence_list => @sentence_list.values}.to_json
	end

	def export_subcorpus(filename)
		if @found
			subgraph = @graph.subcorpus(@sentence_list.values.select{|s| s[:found]}.map{|s| @graph.nodes[s[:id]]})
			@sinatra.headers("Content-Type" => "data:Application/octet-stream; charset=utf8")
			return JSON.pretty_generate(subgraph, :indent => ' ', :space => '').encode('UTF-8')
		end
	end

	def export_data
		if @found
			begin
				anfrage = @sinatra.params[:query]
				@data_table = @graph.teilgraph_ausgeben(@found, anfrage, :string)
				return ''
			rescue StandardError => e
				return e.message
			end
		end
	end

	def export_data_table(filename)
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
		properties = @graph.conf.layer_attributes[layer]

		case command
			when 'n' # new node
				if @sentence
					layer = set_new_layer(parameters[:words], properties)
					properties.merge!(parameters[:attributes])
					@graph.add_anno_node(:attr => properties, :sentence => @sentence)
				end

			when 'e' # new edge
				if @sentence
					layer = set_new_layer(parameters[:words], properties)
					properties.merge!(parameters[:attributes])
					@graph.add_anno_edge(
						:start => element_by_identifier(parameters[:all_nodes][0]),
						:end => element_by_identifier(parameters[:all_nodes][1]),
						:attr => properties
					)
				end

			when 'a' # annotate elements
				if @sentence
					@graph.conf.layers.map{|l| l.attr}.each do |a|
						properties.delete(a)
					end

					layer = set_new_layer(parameters[:words], properties)
					properties.merge!(parameters[:attributes])

					parameters[:elements].each do |element_id|
						if element = element_by_identifier(element_id)
							element.attr.merge!(properties)
							parameters[:keys].each{|k| element.attr.delete(k)}
						end
					end
				end

			when 'd' # delete elements
				if @sentence
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
				if @sentence
					layer = set_new_layer(parameters[:words], properties)
					mother = @graph.add_anno_node(:attr => properties.merge(parameters[:attributes]), :sentence => @sentence)
					(parameters[:nodes] + parameters[:tokens]).each do |node|
						if element = element_by_identifier(node)
							@graph.add_anno_edge(
								:start => mother,
								:end => element,
								:attr => properties.clone
							)
						end
					end
				end

			when 'c', 'h' # attach new child node
				if @sentence
					layer = set_new_layer(parameters[:words], properties)
					daughter = @graph.add_anno_node(:attr => properties.merge(parameters[:attributes]), :sentence => @sentence)
					(parameters[:nodes] + parameters[:tokens]).each do |node|
						if element = element_by_identifier(node)
							@graph.add_anno_edge(
								:start => element,
								:end => daughter,
								:attr => properties.clone
							)
						end
					end
				end

			when 'ns' # create and append new sentence(s)
				old_sentence_nodes = @graph.sentence_nodes
				new_nodes = []
				parameters[:words].each do |s|
					new_nodes << @graph.add_sect_node(:name => s)
					@graph.add_order_edge(:start => new_nodes[-2], :end => new_nodes.last)
				end
				@graph.add_order_edge(:start => old_sentence_nodes.last, :end => new_nodes.first)
				@sentence = new_nodes.first

			when 't' # build tokens and append them
				if @sentence
					@graph.build_tokens(parameters[:words], @sentence)
				end

			when 'ti' # build tokens and insert them
				if @sentence
					knoten = element_by_identifier(parameters[:tokens][0])
					@graph.build_tokens(parameters[:words][1..-1], @sentence, knoten)
				end

			when 's' # change sentence
				@sentence = @graph.sentence_nodes.select{|n| n.name == parameters[:words][0]}[0]

			when 'del' # delete sentence
				if @sentence
					saetze = @graph.sentence_nodes
					index = saetze.index(@sentence) + 1
					index -= 2 if index == saetze.length
					last_sentence = @sentence.node_before
					next_sentence = @sentence.node_after
					# delete nodes
					@sentence.nodes.each{|n| n.delete}
					@sentence.delete
					@graph.add_order_edge(:start => last_sentence, :end => next_sentence)
					# change to next sentence
					@sentence = saetze[index]
				end

			when 'load', 'laden' # clear workspace and load corpus file
				@graph_file.replace('data/' + parameters[:words][0] + '.json')

				@graph.read_json_file(@graph_file)
				sentence_nodes = @graph.sentence_nodes
				if @sentence
					@sentence = sentence_nodes.select{|n| n.name == @sentence.name}[0]
				end
				@sentence = sentence_nodes.first unless @sentence

			when 'add' # load corpus file and add it to the workspace
				@graph_file.replace('')
				addgraph = AnnoGraph.new
				addgraph.read_json_file('data/' + parameters[:words][0] + '.json')
				@graph.merge!(addgraph)

			when 'save', 'speichern' # save workspace to corpus file
				@graph_file.replace(@graph_file.replace('data/' + parameters[:words][0] + '.json')) if parameters[:words][0]
				Dir.mkdir('data') unless File.exist?('data')
				@graph.write_json_file(@graph_file) if @sentence

			when 'clear', 'leeren' # clear workspace
				@graph_file.replace('')
				@graph.clear
				@found = nil
				@sentence = nil

			when 'image' # export sentence as graphics file
				if @sentence
					format = parameters[:words][0]
					name = parameters[:words][1]
					Dir.mkdir('images') if !File.exist?('images')
					generate_graph(format.to_sym, 'images/'+name+'.'+format)
				end

			when 'export' # export corpus in other format
				Dir.mkdir('exports') unless File.exist?('exports')
				format = parameters[:words][0]
				name = parameters[:words][1]
				name2 = parameters[:words][2]
				case format
					when 'paula'
						@graph.export_paula(name, name2 ? name2 : nil)
					when 'salt'
						@graph.export_saltxml(name)
					when 'sql'
						@graph.export_sql(name)
				end

			when 'import' # open text import window
				if parameters[:words].first == 'toolbox'
					return {:modal => 'import', :type => 'toolbox'}
				else
					return {:modal => 'import', :type => 'text'}
				end

			# all following commands are related to annotation @graph expansion -- Experimental!
			when 'project'
				@graph.merkmale_projizieren(@sentence)
			when 'reduce'
				@graph.merkmale_reduzieren(@sentence)

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
				@graph.apply_shortcuts(@sentence)


			when 'exp'
				@graph.expandieren(@sentence)
			when 'exp1'
				@graph.praedikationen_einfuehren(@sentence)
			when 'exp3'
				@graph.referenten_einfuehren(@sentence)
			when 'exp4'
				@graph.argumente_einfuehren(@sentence)
			when 'expe'
				@graph.apply_shortcuts(@sentence)
				@graph.praedikationen_einfuehren(@sentence)
				@graph.referenten_einfuehren(@sentence)
				@graph.argumente_einfuehren(@sentence)
				@graph.argumente_entfernen(@sentence)
				@graph.merkmale_projizieren(@sentence)
			when 'exp-praed'
				#@graph.praedikationen_einfuehren(@sentence)
				@graph.praedikationen_einfuehren(@sentence)
				@graph.referenten_einfuehren(@sentence)
				@graph.argumente_einfuehren(@sentence)
				@graph.argumente_entfernen(@sentence)
				@graph.referenten_entfernen(@sentence)
				# Aufräumen:
				@graph.nodes.values.select{|k| @sentence == nil || k.sentence == @sentence}.clone.each do |k|
					k.referent = nil
					k.praedikation = nil
					k.satz = nil
					k.gesammelte_merkmale = nil
					k.unreduzierte_merkmale = nil
				end
			when 'exp-ref'
				@graph.komprimieren(@sentence)
				@graph.praedikationen_einfuehren(@sentence)
				@graph.referenten_einfuehren(@sentence)
				@graph.argumente_einfuehren(@sentence)
				@graph.argumente_entfernen(@sentence)
				# Aufräumen:
				@graph.nodes.values.select{|k| @sentence == nil || k.sentence == @sentence}.clone.each do |k|
					k.referent = nil
					k.praedikation = nil
					k.satz = nil
					k.gesammelte_merkmale = nil
					k.unreduzierte_merkmale = nil
				end
			when 'exp-arg'
				@graph.komprimieren(@sentence)
				@graph.expandieren(@sentence)
				# Aufräumen:
				@graph.nodes.values.select{|k| @sentence == nil || k.sentence == @sentence}.clone.each do |k|
					k.referent = nil
					k.praedikation = nil
					k.satz = nil
					k.gesammelte_merkmale = nil
					k.unreduzierte_merkmale = nil
				end

			when 'komp'
				@graph.komprimieren(@sentence)
			when 'komp-arg'
				@graph.argumente_entfernen(@sentence)
			when 'komp-ref'
				@graph.referenten_entfernen(@sentence)
			when 'komp-praed'
				@graph.komprimieren(@sentence)
				#@graph.praedikationen_entfernen(@sentence)
				#@graph.adverbialpraedikationen_entfernen(@sentence)
				## Aufräumen:
				#@graph.nodes.values.select{|k| @sentence == nil || k.sentence == @sentence}.clone.each do |k|
				#	k.referent = nil
				#	k.praedikation = nil
				#	k.satz = nil
				#	k.gesammelte_merkmale = nil
				#	k.unreduzierte_merkmale = nil
				#end

		end
		return nil
	end

	def element_by_identifier(identifier)
		i = identifier.scan(/\d/).join.to_i
		case identifier[0]
			when 'm'
				return @sentence
			when 'n'
				return @nodes[i]
			when 'e'
				return @edges[i]
			when 't'
				return @tokens[i]
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
		if new_layer_shortcut = words.select{|w| @graph.conf.layer_shortcuts.keys.include?(w)}.last
			layer = @graph.conf.layer_shortcuts[new_layer_shortcut]
			@sinatra.response.set_cookie('traw_layer', { :value => layer })
			properties.replace(@graph.conf.layer_attributes[layer].to_h)
			return layer
		end
	end

	def documentation(filename)
		@sinatra.send_file('doc/' + filename)
	end

	private

	def validate_config(data)
		result = {}
		data['layers'] = data['layers'] || {}
		data['combinations'] = data['combinations'] || {}
		data['general'].each do |attr, value|
			if attr.match(/_color$/)
				result["general[#{attr}]"] = '' unless value.is_hex_color?
			elsif attr.match(/weight$/)
				result["general[#{attr}]"] = '' unless value.is_number?
			end
		end
		data['layers'].each do |i, layer|
			layer.each do |k, v|
				if k == 'color'
					result["layers[#{i}[#{k}]]"] = '' unless v.is_hex_color?
				elsif k == 'weight'
					result["layers[#{i}[#{k}]]"] = '' unless v.is_number?
				elsif ['name', 'attr', 'shortcut'].include?(k)
					result["layers[#{i}[#{k}]]"] = '' unless v != ''
				end
			end
			['name', 'attr', 'shortcut'].each do |key|
				data['layers'].each do |i2, l2|
					if !layer.equal?(l2) and layer[key] == l2[key]
						result["layers[#{i}[#{key}]]"] = ''
						result["layers[#{i2}[#{key}]]"] = ''
					end
				end
				data['combinations'].each do |i2, c|
					if layer[key] == c[key]
						result["layers[#{i}[#{key}]]"] = ''
						result["combinations[#{i2}[#{key}]]"] = ''
					end
				end
			end
		end
		data['combinations'].each do |i, combination|
			combination.each do |k, v|
				if k == 'color'
					result["combinations[#{i}[#{k}]]"] = '' unless v.is_hex_color?
				elsif k == 'weight'
					result["combinations[#{i}[#{k}]]"] = '' unless v.is_number?
				elsif ['name', 'shortcut'].include?(k)
					result["combinations[#{i}[#{k}]]"] = '' unless v != ''
				end
				if not combination['attr'] or combination['attr'].length == 1
					result["combinations[#{i}[attr]]"] = ''
				end
			end
			['name', 'attr', 'shortcut'].each do |key|
				data['combinations'].each do |i2, c2|
					if !combination.equal?(c2) and combination[key] == c2[key]
						result["combinations[#{i}[#{key}]]"] = ''
						result["combinations[#{i2}[#{key}]]"] = ''
					end
				end
			end
		end
		begin
			@graph.parse_query(data['makros'])
		rescue StandardError => e
			result['makros'] = e.message
		end
		return result.empty? ? true : result
	end

	def generate_graph(format, path)
		puts "Generating graph for sentence \"#{@sentence.name}\"..." if @sentence

		viz_graph = GraphViz.new(
			:G,
			:type => 'digraph',
			:rankdir => 'TB',
			:use => 'dot',
			:ranksep => '.3'
		)
		token_graph = viz_graph.subgraph(:rank => 'same')
		layer_graphs = {}
		@graph.conf.combinations.each do |c|
			layer_graphs[c.attr] = c.weight < 0 ? viz_graph.subgraph(:rank => 'same') : viz_graph.subgraph
		end
		@graph.conf.layers.each do |l|
			layer_graphs[l.attr] = l.weight < 0 ? viz_graph.subgraph(:rank => 'same') : viz_graph.subgraph
		end

		satzinfo = {:textline => '', :meta => ''}

		@tokens = @sentence ? @sentence.sentence_tokens : []
		all_nodes = @sentence ? @sentence.nodes : []
		@nodes = all_nodes.reject{|n| n.type == 't'}
		@edges = all_nodes.map{|n| n.in + n.out}.flatten.uniq.select{|e| e.type == 'a'}
		token_edges = @tokens.map{|t| t.in + t.out}.flatten.uniq.select{|e| e.type == 'o'}
		
		if @filter[:mode] == 'filter'
			@nodes.select!{|n| @filter[:show] == n.fulfil?(@filter[:cond])}
			@edges.select!{|e| @filter[:show] == e.fulfil?(@filter[:cond])}
		end

		satzinfo[:meta] = build_label(@sentence) if @sentence

		@tokens.each_with_index do |token, i|
			color = @graph.conf.token_color
			fontcolor = @graph.conf.token_color
			if @found && @found[:all_nodes].include?(token)
				color = @graph.conf.found_color
				satzinfo[:textline] += '<span class="found_word">' + token.token + '</span> '
			elsif @filter[:mode] == 'hide' and @filter[:show] != token.fulfil?(@filter[:cond])
				color = @graph.conf.filtered_color
				fontcolor = @graph.conf.filtered_color
				satzinfo[:textline] += '<span class="hidden_word">' + token.token + '</span> '
			else
				satzinfo[:textline] += token.token + ' '
			end
			token_graph.add_nodes(
				token.id,
				:fontname => @graph.conf.font,
				:label => HTMLEntities.new.encode(build_label(token, @show_refs ? i : nil), :hexadecimal),
				:shape => 'box',
				:style => 'bold',
				:color => color,
				:fontcolor => fontcolor
			)
		end

		@nodes.each_with_index do |node, i|
			color = @graph.conf.default_color
			add_graphs = []
			if @filter[:mode] == 'hide' and @filter[:show] != node.fulfil?(@filter[:cond])
				color = @graph.conf.filtered_color
			else
				@graph.conf.layers.each do |l|
					if node[l.attr] == 't'
						color = l.color
						add_graphs << layer_graphs[l.attr]
					end
				end
				@graph.conf.combinations.sort{|a,b| a.attr.length <=> b.attr.length}.each do |c|
					if c.attr.all?{|a| node[a] == 't'}
						color = c.color
						add_graphs << layer_graphs[c.attr]
					end
				end
			end
			fontcolor = color
			if @found && @found[:all_nodes].include?(node)
				color = @graph.conf.found_color
			end
			viz_graph.add_nodes(
				node.id,
				:fontname => @graph.conf.font,
				:label => HTMLEntities.new.encode(build_label(node, @show_refs ? i : nil), :hexadecimal),
				:shape => 'box',
				:color => color,
				:fontcolor => fontcolor
			)
			add_graphs.each{|g| g.add_nodes(node.id)}
		end

		@edges.each_with_index do |edge, i|
			color = @graph.conf.default_color
			weight = @graph.conf.edge_weight
			constraint = true
			if @filter[:mode] == 'hide' and @filter[:show] != edge.fulfil?(@filter[:cond])
				color = @graph.conf.filtered_color
			else
				@graph.conf.layers.each do |l|
					if edge[l.attr] == 't'
						color = l.color
						weight = l.weight
						constraint = false if weight == 0
					end
				end
				@graph.conf.combinations.sort{|a,b| a.attr.length <=> b.attr.length}.each do |c|
					if c.attr.all?{|a| edge[a] == 't'}
						color = c.color
						weight = c.weight
					end
				end
			end
			fontcolor = color
			if @found && @found[:all_edges].include?(edge)
				color = @graph.conf.found_color
			end
			viz_graph.add_edges(
				edge.start.id,
				edge.end.id,
				:fontname => @graph.conf.font,
				:label => HTMLEntities.new.encode(build_label(edge, @show_refs ? i : nil),
				:hexadecimal),
				:color=> color,
				:fontcolor => fontcolor,
				:weight => weight,
				:constraint => constraint
			)
		end

		token_edges.each do |edge|
			#len => 0
			viz_graph.add_edges(edge.start.id, edge.end.id, :style => 'invis', :weight => 100)
		end

		viz_graph.output(format => '"'+path+'"')

		return satzinfo
	end

	def build_label(e, i = nil)
		label = ''
		display_attr = e.attr.reject{|k,v| (@graph.conf.layers.map{|l| l.attr}).include?(k)}
		if e.kind_of?(Node)
			if e.type == 's'
				display_attr.each do |key,value|
					label += "#{key}: #{value}<br/>"
				end
			elsif e.type == 't'
				display_attr.each do |key, value|
					case key
						when 'token'
							label = "#{value}\n#{label}"
						else
							label += "#{key}: #{value}\n"
					end
				end
				if i
					label += "t" + i.to_s
				end
			else # normaler Knoten
				display_attr.each do |key,value|
					case key
						when 'cat'
							label = "#{value}\n#{label}"
						else
							label += "#{key}: #{value}\n"
					end
				end
				if i
					label += "n" + i.to_s
				end
			end
		elsif e.kind_of?(Edge)
			display_attr.each do |key,value|
				case key
					when 'cat'
						label = "#{value}\n#{label}"
					else
						label += "#{key}: #{value}\n"
				end
			end
			if i
				label += "e" + i.to_s
			end
		end
		return label
	end

end

class String

	def is_hex_color?
		self.match(/^#[0-9a-fA-F]{6}$/)
	end

	def is_number?
		self.match(/^\s*-?[0-9]+\s*$/)
	end

	def de_escape!
		self.gsub!(/\\(.)/) do |s|
			case $1
			when '"'
				"\""
			when '\\'
				"\\"
			when 'a'
				"\a"
			when 'b'
				"\b"
			when 'n'
				"\n"
			when 'r'
				"\r"
			when 's'
				"\s"
			when 't'
				"\t"
			else
				$&
			end
		end
	end

end
