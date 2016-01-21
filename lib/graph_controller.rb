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

require 'yaml.rb'
require 'graphviz.rb'
	require 'open3.rb'
require 'htmlentities.rb'
require_relative 'log.rb'

class GraphController
	attr_writer :sinatra
	attr_reader :graph, :log, :sentence_list, :graph_file, :search_result

	def initialize
		@graph = AnnoGraph.new
		@log = Log.new(@graph)
		@graph_file = ''
		@data_table = nil
		@search_result = ''
		@sentence_list = {}
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
		@sentence = @graph.nodes[@sinatra.request.cookies['traw_sentence'].to_i]
		return generate_graph.merge(
			:sentence_list => set_sentence_list.values,
			:sentence_changed => true
		).to_json
	end

	def toggle_refs
		@show_refs = !@show_refs
		return generate_graph.merge(
			:sentence_changed => false
		).to_json
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
		@cmd_error_messages = []
		puts 'Processing command: "' + @sinatra.params[:txtcmd] + '"'
		set_cmd_cookies
		@sentence = @sinatra.params[:sentence] == '' ? nil : @graph.nodes[@sinatra.params[:sentence].to_i]
		begin
			value = execute_command(@sinatra.params[:txtcmd], @sinatra.params[:layer])
		rescue StandardError => e
			@cmd_error_messages << e.message
		end
		return value.to_json if value.is_a?(Hash)
		return sentence_settings_and_graph.merge(
			:graph_file => @graph_file,
			:current_annotator => @graph.current_annotator ? @graph.current_annotator.name : '',
			:command => value,
			:messages => @cmd_error_messages
		).to_json
	end

	def change_sentence
		set_cmd_cookies
		@sentence = @graph.nodes[@sinatra.params[:sentence].to_i]
		return generate_graph.merge(
			:sentence_changed => true
		).to_json
	end

	def filter
		set_filter_cookies
		mode = @sinatra.params[:mode].partition(' ')
		@filter = {:cond => @graph.parse_attributes(@sinatra.params[:filter])[:op], :mode => mode[0], :show => (mode[2] == 'rest')}
		return generate_graph.merge(
			:sentence_changed => false,
			:filter_applied => true
		).to_json
	end

	def search
		set_cookie('traw_query', @sinatra.params[:query])
		@found = {:tg => []}
		begin
			@found[:tg] = @graph.teilgraph_suchen(@sinatra.params[:query])
			@search_result = @found[:tg].length.to_s + ' matches'
		rescue StandardError => e
			@search_result = error_message_html(e.message)
		end
		@found[:all_nodes] = @found[:tg].map{|tg| tg.nodes}.flatten.uniq
		@found[:all_edges] = @found[:tg].map{|tg| tg.edges}.flatten.uniq
		@sentence_list.each{|id, h| h[:found] = false}
		set_found_sentences
		return generate_graph.merge(
			:sentence_list => @sentence_list.values,
			:search_result => @search_result,
			:sentence_changed => false
		).to_json
	end

	def clear_search
		@found = nil
		@search_result = ''
		return generate_graph.merge(
			:sentence_list => set_sentence_list.values,
			:search_result => @search_result,
			:sentence_changed => false
		).to_json
	end

	['config', 'metadata', 'makros', 'tagset', 'speakers', 'annotators', 'file'].each do |form_name|
		define_method("#{form_name}_form") do
			@sinatra.haml(
				:"#{form_name}_form",
				:locals => {
					:graph => @graph
				}
			)
		end
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

	def save_metadata
		@graph.info = {}
		@sinatra.params['keys'].each do |i, key|
			@graph.info[key.strip] = @sinatra.params['values'][i].strip if key.strip != ''
		end
		return true.to_json
	end

	def save_speakers
		@sinatra.params['ids'].each do |i, id|
			attributes = @sinatra.params['attributes'][i].parse_parameters[:attributes]
			if id != ''
				@graph.nodes[id].attr = Attributes.new(:host => @graph.nodes[id], :raw => true, :attr => attributes)
			else
				@graph.add_speaker_node(:attr => attributes)
			end
		end
		return true.to_json
	end

	def save_annotators
		# validate
		if @sinatra.params['names'].any?{|i, name| name == ''} or
			 @sinatra.params['names'].values.length != @sinatra.params['names'].values.uniq.length
			return false.to_json
		end
		# delete
		@graph.delete_annotators(
			@graph.annotators.select{|a| !@sinatra.params['ids'].values.map(&:to_i).include?(a.id)}
		)
		# create/update
		@sinatra.params['ids'].each do |i, id|
			if annotator = @graph.get_annotator(:id => id)
				annotator.name = @sinatra.params['names'][i]
				annotator.info = @sinatra.params['infos'][i]
			else
				@graph.annotators << Annotator.new(
					:graph => @graph,
					:name => @sinatra.params['names'][i],
					:info => @sinatra.params['infos'][i]
				)
			end
		end
		return true.to_json
	end

	def save_makros
		@graph.anno_makros = {}
		@sinatra.params['keys'].each do |i, key|
			@graph.anno_makros[key.strip] = @sinatra.params['values'][i].parse_parameters[:attributes]
		end
		return true.to_json
	end

	def save_tagset
		tagset_hash = @sinatra.params['keys'].values.zip(@sinatra.params['values'].values).map{|a| {'key' => a[0], 'values' => a[1]}}
		@graph.tagset = Tagset.new(tagset_hash)
		return true.to_json
	end

	def save_file
		@graph.file_settings.clear
		[:compact, :save_log, :separate_log].each do |property|
			@graph.file_settings[property] = !!@sinatra.params[property.to_s]
		end
		return true.to_json
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

	def new_annotator(i)
		@sinatra.haml(
			:annotators_form_segment,
			:locals => {
				:annotator => Annotator.new(:graph => @graph, :id => 0),
				:i => i
			}
		)
	end

	def import_form(type)
		modal = :"import_form_#{type}"
		@sinatra.haml(
			modal,
			:locals => {
				:nlp => NLP
			}
		)
	end

	def import(type)
		clear_workspace
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
		set_cookie('traw_sentence', @sentence.id)
		return {
			:sentence_list => @sentence_list.values,
			:current_annotator => @graph.current_annotator ? @graph.current_annotator.name : ''
		}.to_json
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
				return error_message_html(e.message)
			end
		end
	end

	def export_data_table(filename)
		if @data_table
			@sinatra.headers("Content-Type" => "data:Application/octet-stream; charset=utf8")
			return @data_table
		end
	end

	def annotate_query
		begin
			search_result_preserved = @graph.teilgraph_annotieren(@found, @sinatra.params[:query])
		rescue StandardError => e
			return {:search_result => error_message_html(e.message)}.to_json
		end
		unless search_result_preserved
			@found = nil
			@search_result = ''
		end
		return generate_graph.merge(
			:sentence_list => set_sentence_list.values,
			:search_result => @search_result,
			:sentence_changed => false
		).to_json
	end

	def go_to_step(i)
		@log.go_to_step(i.to_i)
		reset_sentence
		return sentence_settings_and_graph.to_json
	end

	def get_log_update
		{
			:current_index => @log.current_index,
			:max_index => @log.max_index,
			:html => @sinatra.haml(
				:log_step,
				:locals => {
					:log => @log,
					:i => @log.max_index
				}
			)
		}.to_json
	end

	def get_log_table
		@sinatra.haml(
			:log_table,
			:locals => {:log => @log}
		)
	end

	def documentation(filename)
		@sinatra.send_file('doc/' + filename)
	end

	private

	def clear_workspace
		@graph_file.replace('')
		@graph.clear
		@found = nil
		@sentence = nil
		@log = Log.new(@graph)
	end

	def sentence_settings_and_graph
		set_cookie('traw_sentence', @sentence ? @sentence.id : nil)
		return generate_graph.merge(
			:sentence_list => set_sentence_list.values,
			:sentence_changed => (@sentence && @sinatra.request.cookies['traw_sentence'].to_i == @sentence.id) ? false : true
		)
	end

	def extract_attributes(parameters)
		allowed_attributes(
			makros_to_attributes(parameters[:words]).merge(parameters[:attributes])
		)
	end

	def allowed_attributes(attr)
		allowed_attr = @graph.allowed_attributes(attr)
		if (forbidden = attr.select{|k, v| v}.keys - allowed_attr.keys) != []
			@cmd_error_messages << "Illicit annotation: #{forbidden.map{|k| k+':'+attr[k]} * ' '}"
		end
		return allowed_attr
	end

	def makros_to_attributes(words)
		words.map{|word| @graph.anno_makros[word]}.compact.reduce(:merge) || {}
	end

	def error_message_html(message)
		 '<span class="error_message">' + message.gsub("\n", '<br/>') + '</span>'
	end

	def build_label(e, i = nil)
		label = ''
		display_attr = e.attr.reject{|k,v| (@graph.conf.layers.map{|l| l.attr}).include?(k)}
		if e.is_a?(Node)
			if e.type == 's'
				label += display_attr.map{|key, value| "#{key}: #{value}<br/>"}.join
			elsif e.type == 't'
				display_attr.each do |key, value|
					case key
					when 'token'
						label = "#{value}\n#{label}"
					else
						label += "#{key}: #{value}\n"
					end
				end
				label += "t#{i}" if i
			else # normaler Knoten
				display_attr.each do |key,value|
					case key
					when 'cat'
						label = "#{value}\n#{label}"
					else
						label += "#{key}: #{value}\n"
					end
				end
				label += "n#{i}" if i
			end
		elsif e.is_a?(Edge)
			display_attr.each do |key,value|
				case key
				when 'cat'
					label = "#{value}\n#{label}"
				else
					label += "#{key}: #{value}\n"
				end
			end
			label += "e#{i}" if i
		end
		return label
	end

	def set_cookie(key, value)
		@sinatra.response.set_cookie(key, {:value => value, :path => '/', :expires => Time.new(9999, 12, 31)})
	end

	def check_cookies
		['traw_sentence', 'traw_layer', 'traw_cmd', 'traw_query'].each do |cookie_name|
			set_cookie(cookie_name, '') unless @sinatra.request.cookies[cookie_name]
		end
	end

	def element_by_identifier(identifier)
		i = identifier.scan(/\d/).join.to_i
		{
			'm' => @sentence,
			'n' => @nodes[i],
			'e' => @edges[i],
			't' => @tokens[i],
		}[identifier[0]]
	end

	def extract_elements(identifiers)
		identifiers.map{|id| element_by_identifier(id)}.compact
	end

	def execute_command(command_line, layer)
		command, foo, string = command_line.strip.partition(' ')
		parameters = string.parse_parameters
		properties = @graph.conf.layer_attributes[layer]

		case command
		when 'n' # new node
			sentence_set?
			log_step = @log.add_step(:command => command_line)
			layer = set_new_layer(parameters[:words], properties)
			properties.merge!(extract_attributes(parameters))
			@graph.add_anno_node(:attr => properties, :sentence => @sentence, :log => log_step)

		when 'e' # new edge
			sentence_set?
			log_step = @log.add_step(:command => command_line)
			layer = set_new_layer(parameters[:words], properties)
			properties.merge!(extract_attributes(parameters))
			@graph.add_anno_edge(
				:start => element_by_identifier(parameters[:all_nodes][0]),
				:end => element_by_identifier(parameters[:all_nodes][1]),
				:attr => properties,
				:log => log_step
			)
			undefined_references?(parameters[:all_nodes][0..1])

		when 'a' # annotate elements
			sentence_set?
			log_step = @log.add_step(:command => command_line)
			@graph.conf.layers.map{|l| l.attr}.each do |a|
				properties.delete(a)
			end
			layer = set_new_layer(parameters[:words], properties)
			properties.merge!(extract_attributes(parameters))
			extract_elements(parameters[:elements]).each do |element|
				element.annotate(properties, log_step)
			end
			undefined_references?(parameters[:elements])

		when 'd' # delete elements
			sentence_set?
			log_step = @log.add_step(:command => command_line)
			extract_elements(parameters[:nodes] + parameters[:edges]).each do |element|
				element.delete(log_step)
			end
			extract_elements(parameters[:tokens]).each do |element|
				element.remove_token(log_step)
			end
			undefined_references?(parameters[:elements])

		when 'l' # set layer
			layer = set_new_layer(parameters[:words], properties)

		when 'p', 'g' # group under new parent node
			sentence_set?
			log_step = @log.add_step(:command => command_line)
			layer = set_new_layer(parameters[:words], properties)
			@graph.add_parent_node(
				extract_elements(parameters[:nodes] + parameters[:tokens]),
				properties.merge(extract_attributes(parameters)),
				properties.clone,
				@sentence,
				log_step
			)
			undefined_references?(parameters[:nodes] + parameters[:tokens])

		when 'c', 'h' # attach new child node
			sentence_set?
			log_step = @log.add_step(:command => command_line)
			layer = set_new_layer(parameters[:words], properties)
			@graph.add_child_node(
				extract_elements(parameters[:nodes] + parameters[:tokens]),
				properties.merge(extract_attributes(parameters)),
				properties.clone,
				@sentence,
				log_step
			)
			undefined_references?(parameters[:nodes] + parameters[:tokens])

		when 'ni' # build node and "insert in edge"
			sentence_set?
			log_step = @log.add_step(:command => command_line)
			layer = set_new_layer(parameters[:words], properties)
			properties.merge!(extract_attributes(parameters))
			extract_elements(parameters[:edges]).each do |edge|
				@graph.insert_node(edge, properties, log_step)
			end
			undefined_references?(parameters[:edges])

		when 'di', 'do' # remove node and connect parent/child nodes
			sentence_set?
			log_step = @log.add_step(:command => command_line)
			layer = set_new_layer(parameters[:words], properties)
			extract_elements(parameters[:nodes]).each do |node|
				@graph.delete_and_join(node, command == 'di' ? :in : :out, log_step)
			end
			undefined_references?(parameters[:nodes])

		when 'ns' # create and append new sentence(s)
			log_step = @log.add_step(:command => command_line)
			old_sentence_nodes = @graph.sentence_nodes
			new_nodes = []
			parameters[:words].each do |s|
				new_nodes << @graph.add_sect_node(:name => s, :log => log_step)
				@graph.add_order_edge(:start => new_nodes[-2], :end => new_nodes.last, :log => log_step)
			end
			@graph.add_order_edge(:start => old_sentence_nodes.last, :end => new_nodes.first, :log => log_step)
			@sentence = new_nodes.first

		when 't' # build tokens and append them
			sentence_set?
			log_step = @log.add_step(:command => command_line)
			@graph.build_tokens(parameters[:words], :sentence => @sentence, :log => log_step)

		when 'tb', 'ti' # build tokens and insert them before given token
			sentence_set?
			log_step = @log.add_step(:command => command_line)
			undefined_references?(parameters[:tokens][0..0])
			node = element_by_identifier(parameters[:tokens][0])
			@graph.build_tokens(parameters[:words][1..-1], :next_token => node, :log => log_step)

		when 'ta' # build tokens and insert them after given token
			sentence_set?
			log_step = @log.add_step(:command => command_line)
			undefined_references?(parameters[:tokens][0..0])
			node = element_by_identifier(parameters[:tokens][0])
			@graph.build_tokens(parameters[:words][1..-1], :last_token => node, :log => log_step)

		when 'undo', 'z'
			@log.undo
			reset_sentence

		when 'redo', 'y'
			@log.redo
			reset_sentence

		when 's' # change sentence
			@sentence = @graph.sentence_nodes.select{|n| n.name == parameters[:words][0]}[0]

		when 'user', 'annotator'
			@log.user = @graph.set_annotator(:name => parameters[:string])

		when 'del' # delete sentence
			sentences = if parameters[:words] != []
				@graph.sentence_nodes.select do |n|
					parameters[:words].any?{|arg|
						!arg.match(/^\/.*\/$/) and n.name == arg or
						arg.match(/^\/.*\/$/) and n.name.match(Regexp.new(arg[1..-2]))
					}
				end
			elsif sentence_set?
				command_line << ' ' + @sentence.name
				[@sentence]
			else
				[]
			end
			log_step = @log.add_step(:command => command_line)
			sentences.each do |sentence|
				# change to next sentence
				@sentence = sentence.node_after || sentence.node_before if sentence == @sentence
				# join remaining sentences
				@graph.add_order_edge(:start => sentence.node_before, :end => sentence.node_after, :log => log_step)
				# delete nodes
				sentence.nodes.each{|n| n.delete(log_step)}
				sentence.delete(log_step)
			end

		when 'load' # clear workspace and load corpus file
			clear_workspace
			log_hash = @graph.read_json_file(file_path(parameters[:words][0]))
			@graph_file.replace(file_path(parameters[:words][0]))
			if @graph.file_settings[:separate_log]
				begin
					@log = Log.new_from_file(@graph, @graph_file.sub(/.json$/, '.log.json'))
				rescue
					@log = Log.new(@graph, nil, log_hash)
				end
			else
				@log = Log.new(@graph, nil, log_hash)
			end
			sentence_nodes = @graph.sentence_nodes
			@sentence = sentence_nodes.select{|n| n.name == @sentence.name}[0] if @sentence
			@sentence = sentence_nodes.first unless @sentence

		when 'append', 'add' # load corpus file and append it to the workspace
			addgraph = AnnoGraph.new
			addgraph.read_json_file(file_path(parameters[:words][0]))
			@graph.merge!(addgraph)
			@found = nil

		when 'save' # save workspace to corpus file
			raise 'Please specify a file name!' if @graph_file == '' and !parameters[:words][0]
			@graph_file.replace(file_path(parameters[:words][0])) if parameters[:words][0]
			dir = @graph_file.rpartition('/').first
			FileUtils.mkdir_p(dir) unless dir == '' or File.exist?(dir)
			if @graph.file_settings[:save_log] && !@graph.file_settings[:separate_log]
				@graph.write_json_file(@graph_file, @graph.file_settings[:compact], {:log => @log})
			else
				@graph.write_json_file(@graph_file, @graph.file_settings[:compact])
			end
			if @graph.file_settings[:separate_log]
				@log.write_json_file(@graph_file.sub(/.json$/, '.log.json'), @graph.file_settings[:compact])
			end

		when 'clear' # clear workspace
			clear_workspace

		when 'image' # export sentence as graphics file
			sentence_set?
			format = parameters[:words][0]
			name = parameters[:words][1]
			Dir.mkdir('images') unless File.exist?('images')
			generate_graph(format.to_sym, 'images/'+name+'.'+format)

		when 'export' # export corpus in other format or export graph configurations
			Dir.mkdir('exports') unless File.exist?('exports')
			format = parameters[:words][0]
			name = parameters[:words][1]
			name2 = parameters[:words][2]
			case format
			when 'paula'
				@graph.export_paula(name, name2)
			when 'salt'
				@graph.export_saltxml(name)
			when 'sql'
				@graph.export_sql(name)
			when 'config'
				@graph.export_config(name)
			when 'tagset'
				@graph.export_tagset(name)
			when 'annotators'
				@graph.export_annotators(name)
			else
				raise "Unknown export format: #{format}"
			end

		when 'import' # open import window or imports graph configurations
			type = parameters[:words][0]
			name = parameters[:words][1]
			case type
			when 'config'
				@graph.import_config(name)
			when 'tagset'
				@graph.import_tagset(name)
			when 'annotators'
				@graph.import_annotators(name)
			when 'toolbox'
				return {:modal => 'import', :type => 'toolbox'}
			when 'text'
				return {:modal => 'import', :type => 'text'}
			else
				raise "Unknown import type"
			end

		when 'config', 'tagset', 'metadata', 'makros', 'speakers', 'annotators', 'file'
			return {:modal => command}

		when ''
		else
			raise "Unknown command \"#{command}\""
		end
		return command
	end

	def generate_graph(format = :svg, path = 'public/graph.svg')
		puts "Generating graph for sentence \"#{@sentence.name}\"..." if @sentence
		satzinfo = {:textline => '', :meta => ''}

		@tokens     = @sentence ? @sentence.sentence_tokens : []
		all_nodes   = @sentence ? @sentence.nodes : []
		@nodes      = all_nodes.reject{|n| n.type == 't'}
		all_edges   = all_nodes.map{|n| n.in + n.out}.flatten.uniq
		@edges      = all_edges.select{|e| e.type == 'a'}
		order_edges = all_edges.select{|e| e.type == 'o'}

		if @filter[:mode] == 'filter'
			@nodes.select!{|n| @filter[:show] == n.fulfil?(@filter[:cond])}
			@edges.select!{|e| @filter[:show] == e.fulfil?(@filter[:cond])}
		end

		satzinfo[:meta] = build_label(@sentence) if @sentence

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
		# speaker subgraphs
		if (speakers = @graph.speaker_nodes.select{|sp| @tokens.map{|t| t.speaker}.include?(sp)}) != []
			speaker_graphs = Hash[speakers.map{|s| [s, viz_graph.subgraph(:rank => 'same')]}]
			# induce speaker labels and layering of speaker graphs:
			gv_speaker_nodes = []
			speaker_graphs.each do |speaker_node, speaker_graph|
				gv_speaker_nodes << speaker_graph.add_nodes(
					's' + speaker_node.id.to_s,
					{:shape => 'plaintext', :label => speaker_node['name'], :fontname => @graph.conf.font}
				)
				viz_graph.add_edges(gv_speaker_nodes[-2], gv_speaker_nodes[-1], {:style => 'invis'}) if gv_speaker_nodes.length > 1
			end
			timeline_graph = viz_graph.subgraph(:rank => 'same')
			gv_anchor = timeline_graph.add_nodes('anchor', {:style => 'invis'})
			viz_graph.add_edges(gv_speaker_nodes[-1], gv_anchor, {:style => 'invis'})
		end

		@tokens.each_with_index do |token, i|
			options = {
				:fontname => @graph.conf.font,
				:label => HTMLEntities.new.encode(build_label(token, @show_refs ? i : nil), :hexadecimal),
				:shape => 'box',
				:style => 'bold',
				:color => @graph.conf.token_color,
				:fontcolor => @graph.conf.token_color
			}
			if @found && @found[:all_nodes].include?(token)
				options[:color] = @graph.conf.found_color
				satzinfo[:textline] += '<span class="found_word">' + token.token + '</span> '
			elsif @filter[:mode] == 'hide' and @filter[:show] != token.fulfil?(@filter[:cond])
				options[:color] = @graph.conf.filtered_color
				options[:fontcolor]= @graph.conf.filtered_color
				satzinfo[:textline] += '<span class="hidden_word">' + token.token + '</span> '
			else
				satzinfo[:textline] += token.token + ' '
			end
			unless token.speaker
				token_graph.add_nodes(token.id.to_s, options)
			else
				# create token and point on timeline:
				gv_token = speaker_graphs[token.speaker].add_nodes(token.id.to_s, options)
				gv_time  = timeline_graph.add_nodes('t' + token.id.to_s, {:shape => 'plaintext', :label => "#{token.start}\n#{token.end}", :fontname => @graph.conf.font})
				# add ordering edge from speaker to speaker's first token
				viz_graph.add_edges('s' + token.speaker.id.to_s, gv_token, {:style => 'invis'}) if i == 0
				# multiple lines between token and point on timeline in order to force correct order:
				viz_graph.add_edges(gv_token, gv_time, {:weight => 9999, :style => 'invis'})
				viz_graph.add_edges(gv_token, gv_time, {:arrowhead => 'none', :weight => 9999})
				viz_graph.add_edges(gv_token, gv_time, {:weight => 9999, :style => 'invis'})
				# order points on timeline:
				if i > 0
					viz_graph.add_edges('t' + @tokens[i-1].id.to_s, gv_time, {:arrowhead => 'none'})
				else
					viz_graph.add_edges(gv_anchor, gv_time, {:style => 'invis'})
				end
			end
		end

		@nodes.each_with_index do |node, i|
			options = {
				:fontname => @graph.conf.font,
				:color => @graph.conf.default_color,
				:shape => 'box',
				:label => HTMLEntities.new.encode(build_label(node, @show_refs ? i : nil), :hexadecimal),
			}
			add_graphs = []
			if @filter[:mode] == 'hide' and @filter[:show] != node.fulfil?(@filter[:cond])
				options[:color] = @graph.conf.filtered_color
			else
				@graph.conf.layers.each do |l|
					if node[l.attr] == 't'
						options[:color] = l.color
						add_graphs << layer_graphs[l.attr]
					end
				end
				@graph.conf.combinations.sort{|a,b| a.attr.length <=> b.attr.length}.each do |c|
					if c.attr.all?{|a| node[a] == 't'}
						options[:color] = c.color
						add_graphs << layer_graphs[c.attr]
					end
				end
			end
			options[:fontcolor] = options[:color]
			if @found && @found[:all_nodes].include?(node)
				options[:color] = @graph.conf.found_color
				options[:penwidth] = 2
			end
			viz_graph.add_nodes(node.id.to_s, options)
			add_graphs.each{|g| g.add_nodes(node.id.to_s)}
		end

		@edges.each_with_index do |edge, i|
			options = {
				:fontname => @graph.conf.font,
				:label => HTMLEntities.new.encode(build_label(edge, @show_refs ? i : nil), :hexadecimal),
				:color => @graph.conf.default_color,
				:weight => @graph.conf.edge_weight,
				:constraint => true
			}
			if @filter[:mode] == 'hide' and @filter[:show] != edge.fulfil?(@filter[:cond])
				options[:color] = @graph.conf.filtered_color
			else
				@graph.conf.layers.each do |l|
					if edge[l.attr] == 't'
						options[:color] = l.color
						options[:weight]= l.weight
						options[:constraint] = false if options[:weight] == 0
					end
				end
				@graph.conf.combinations.sort{|a,b| a.attr.length <=> b.attr.length}.each do |c|
					if c.attr.all?{|a| edge[a] == 't'}
						options[:color] = c.color
						options[:weight] = c.weight
					end
				end
			end
			options[:fontcolor] = options[:color]
			if @found && @found[:all_edges].include?(edge)
				options[:color] = @graph.conf.found_color
				options[:penwidth] = 2
			end
			viz_graph.add_edges(edge.start.id.to_s, edge.end.id.to_s, options)
		end

		order_edges.each do |edge|
			viz_graph.add_edges(edge.start.id.to_s, edge.end.id.to_s, :style => 'invis', :weight => 100)
		end

		viz_graph.output(format => '"'+path+'"')

		return satzinfo
	end

	def sentence_set?
		if @sentence
			return true
		else
			raise 'Create a sentence first!'
		end
	end

	def reset_sentence
		@sentence = @graph.sentence_nodes.first unless @graph.sentence_nodes.include?(@sentence)
	end

	def set_cmd_cookies
		set_cookie('traw_layer', @sinatra.params[:layer]) if @sinatra.params[:layer]
		set_cookie('traw_cmd', @sinatra.params[:txtcmd]) if @sinatra.params[:txtcmd]
		set_cookie('traw_sentence', @sinatra.params[:sentence]) if @sinatra.params[:sentence]
	end

	def set_filter_cookies
		set_cookie('traw_filter', @sinatra.params[:filter])
		set_cookie('traw_filter_mode', @sinatra.params[:mode])
	end

	def set_new_layer(words, properties)
		if new_layer_shortcut = words.select{|w| @graph.conf.layer_shortcuts.keys.include?(w)}.last
			layer = @graph.conf.layer_shortcuts[new_layer_shortcut]
			set_cookie('traw_layer', layer)
			properties.replace(@graph.conf.layer_attributes[layer])
			return layer
		end
	end

	def set_found_sentences
		(@found[:all_nodes].map{|n| n.sentence.id} + @found[:all_edges].map{|e| e.end.sentence.id}).uniq.each do |s|
			@sentence_list[s][:found] = true
		end
	end

	def set_sentence_list(h = {})
		@sentence_list = Hash[@graph.sentence_nodes.map{|s| [s.id, {:id => s.id, :name => s.name, :found => false}]}]
		set_found_sentences if !h[:clear] and @found
		@sentence_list
	end

	def undefined_references?(ids)
		undefined_ids = ids.select{|id| !element_by_identifier(id)}
		@cmd_error_messages << "Undefined element(s): #{undefined_ids * ', '}" unless undefined_ids.empty?
	end

	def file_path(input)
		(input[0] == '/' ? '' : 'data/') + input + (input.match(/\.json$/) ? '' : '.json')
	end

	def validate_config(data)
		result = {}
		data['layers'] = data['layers'] || {}
		data['combinations'] = data['combinations'] || {}
		data['general'].each do |attr, value|
			if attr.match(/_color$/)
				result["general[#{attr}]"] = true unless value.is_hex_color?
			elsif attr.match(/weight$/)
				result["general[#{attr}]"] = true unless value.is_number?
			end
		end
		data['layers'].each do |i, layer|
			layer.each do |k, v|
				if k == 'color'
					result["layers[#{i}[#{k}]]"] = true unless v.is_hex_color?
				elsif k == 'weight'
					result["layers[#{i}[#{k}]]"] = true unless v.is_number?
				elsif ['name', 'attr', 'shortcut'].include?(k)
					result["layers[#{i}[#{k}]]"] = true unless v != ''
				end
			end
			['name', 'attr', 'shortcut'].each do |key|
				data['layers'].each do |i2, l2|
					if !layer.equal?(l2) and layer[key] == l2[key]
						result["layers[#{i}[#{key}]]"] = true
						result["layers[#{i2}[#{key}]]"] = true
					end
				end
				data['combinations'].each do |i2, c|
					if layer[key] == c[key]
						result["layers[#{i}[#{key}]]"] = true
						result["combinations[#{i2}[#{key}]]"] = true
					end
				end
			end
		end
		data['combinations'].each do |i, combination|
			combination.each do |k, v|
				if k == 'color'
					result["combinations[#{i}[#{k}]]"] = true unless v.is_hex_color?
				elsif k == 'weight'
					result["combinations[#{i}[#{k}]]"] = true unless v.is_number?
				elsif ['name', 'shortcut'].include?(k)
					result["combinations[#{i}[#{k}]]"] = true unless v != ''
				end
				if !combination['attr'] or combination['attr'].length == 1
					result["combinations[#{i}[attr]]"] = true
				end
			end
			['name', 'attr', 'shortcut'].each do |key|
				data['combinations'].each do |i2, c2|
					if !combination.equal?(c2) and combination[key] == c2[key]
						result["combinations[#{i}[#{key}]]"] = true
						result["combinations[#{i2}[#{key}]]"] = true
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
