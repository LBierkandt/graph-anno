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
require 'htmlentities.rb'
require_relative 'log.rb'
require_relative 'dot_graph.rb'

class GraphController
	attr_writer :sinatra
	attr_reader :graph, :log, :graph_file, :search_result

	def initialize
		@graph = AnnoGraph.new
		@log = Log.new(@graph)
		@graph_file = ''
		@data_table = nil
		@search_result = ''
		@section_list = {}
		@sections = []
		@current_sections = nil
		@tokens = []
		@nodes = []
		@edges = []
		@show_refs = true
		@found = nil
		@filter = {:mode => 'unfilter'}
		@windows = {}
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
		generate_graph.merge(
			:current_sections => @current_sections ? current_section_ids : nil,
			:sections => set_sections,
			:sections_changed => true
		).to_json
	end

	def toggle_refs
		@show_refs = !@show_refs
		return generate_graph.merge(
			:sections_changed => false
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
		begin
			value = execute_command(@sinatra.params[:txtcmd], @sinatra.params[:layer])
		rescue StandardError => e
			@cmd_error_messages << e.message
		end
		return value.to_json if value.is_a?(Hash)
		return section_settings_and_graph.merge(
			:graph_file => @graph_file,
			:current_annotator => @graph.current_annotator ? @graph.current_annotator.name : '',
			:command => value,
			:windows => @windows,
			:messages => @cmd_error_messages
		).to_json
	end

	def change_sentence
		set_section(@sinatra.params[:sentence])
		return generate_graph.merge(
			:sections_changed => true
		).to_json
	end

	def filter
		set_filter_cookies
		mode = @sinatra.params[:mode].partition(' ')
		@filter = {:cond => @graph.parse_attributes(@sinatra.params[:filter])[:op], :mode => mode[0], :show => (mode[2] == 'rest')}
		return generate_graph.merge(
			:sections_changed => false,
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
		@found[:all_nodes] = @found[:tg].map(&:nodes).flatten.uniq
		@found[:all_edges] = @found[:tg].map(&:edges).flatten.uniq
		@section_list.each{|id, h| h[:found] = false}
		set_found_sentences
		return generate_graph.merge(
			:sections => @sections,
			:current_sections => current_section_ids,
			:search_result => @search_result,
			:sections_changed => false
		).to_json
	end

	def clear_search
		@found = nil
		@search_result = ''
		return generate_graph.merge(
			:sections => set_sections,
			:search_result => @search_result,
			:sections_changed => false
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

	def new_form_segment(i)
		@sinatra.haml(
			@sinatra.params[:partial].to_sym,
			:locals => {
				:i => i,
				:graph => @graph,
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
		params = {
			'anno' => {'keys' => [], 'values' => []},
			'search' => {'names' => [], 'queries' => []},
		}.merge(@sinatra.params)
		begin
			@graph.anno_makros = Hash[
				params['anno']['keys'].map{|i, key|
					[key.strip, params['anno']['values'][i].parse_parameters[:attributes]] unless key.empty?
				}.compact
			]
			@graph.create_layer_makros
			@graph.makros_plain = params['search']['names'].map{|i, name|
				"def #{name} #{params['search']['queries'][i]}" unless name.empty?
			}.compact
			@graph.makros += @graph.parse_query(@graph.makros_plain * "\n")['def']
		rescue StandardError => e
			return {:errors => e.message}.to_json
		end
		return true.to_json
	end

	def save_tagset
		params = {'keys' => {}, 'values' => {}}.merge(@sinatra.params)
		tagset_hash = params['keys'].values.zip(params['values'].values).map{|a| {'key' => a[0], 'values' => a[1]}}
		@graph.tagset = Tagset.new(tagset_hash)
		return true.to_json
	end

	def save_file
		@graph.file_settings.clear
		[:compact, :save_log, :separate_log, :save_windows].each do |property|
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
		set_sections(:clear => true)
		@current_sections = [@graph.nodes[@section_list.keys.first]]
		return {
			:current_sections => current_section_ids,
			:sections => @sections,
			:current_annotator => @graph.current_annotator ? @graph.current_annotator.name : ''
		}.to_json
	end

	def export_subcorpus(filename)
		if @found
			subgraph = @graph.subcorpus(@section_list.values.select{|s| s[:found]}.map{|s| @graph.nodes[s[:id]]})
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
			:sections => set_sections,
			:search_result => @search_result,
			:sections_changed => false
		).to_json
	end

	def go_to_step(i)
		@log.go_to_step(i.to_i)
		reset_current_sections
		return section_settings_and_graph.to_json
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

	def save_window_positions
		@windows.merge!(@sinatra.params[:data])
		true
	end

	def documentation(filename)
		@sinatra.send_file('doc/' + filename)
	end

	private

	def current_section_ids
		@current_sections.map{|section| section.id.to_s}
	end

	def clear_workspace
		@graph_file.replace('')
		@graph.clear
		@found = nil
		@current_sections = nil
		@log = Log.new(@graph)
	end

	def section_settings_and_graph
		generate_graph.merge(
			:current_sections => @current_sections ? current_section_ids : nil,
			:sections => set_sections,
			:sections_changed => (@current_sections && @sinatra.params[:sections] && @sinatra.params[:sections] == current_section_ids) ? false : true
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
		display_attr = e.attr.reject{|k,v| (@graph.conf.layers.map(&:attr)).include?(k)}
		if e.is_a?(Node)
			if e.type == 's' || e.type == 'p'
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
		['traw_layer', 'traw_cmd', 'traw_query'].each do |cookie_name|
			set_cookie(cookie_name, '') unless @sinatra.request.cookies[cookie_name]
		end
	end

	def set_section(list)
		if list && list != []
			@current_sections = list.map{|id| @graph.nodes[id.to_i]}
		else
			@current_sections = nil
		end
	end

	def element_by_identifier(identifier)
		i = identifier.scan(/\d/).join.to_i
		{
			'm' => @current_sections,
			's' => @graph.sections_hierarchy(@current_sections)[i],
			'n' => @nodes[i],
			'e' => @edges[i],
			't' => @tokens[i],
		}[identifier[0]]
	end

	def nodes_by_name(nodes, names)
		nodes.select do |n|
			names.any?{|name|
				name.match(/^".*"$/) and n.name == name[1..-2] or
				name.match(/^\/.*\/$/) and n.name.match(Regexp.new(name[1..-2])) or
				n.name == name
			}
		end
	end

	def extract_elements(identifiers)
		identifiers.map{|id| element_by_identifier(id)}.flatten.compact
	end

	def chosen_sections(words, sequences, current_as_default = true)
		if !words.empty? || !sequences.empty?
			nodes_by_name(@graph.section_nodes, words) +
				sequences.map{|sequence|
					first, last = nodes_by_name(@graph.section_nodes, sequence)
					if first and last
						level_sections = first.same_level_sections
						level_sections[level_sections.index(first)..level_sections.index(last)]
					else
						[]
					end
				}.flatten
		elsif sentence_set? && current_as_default
			@command_line << ' ' + @current_sections.map(&:name).join(' ')
			@current_sections
		elsif current_as_default
			[]
		else
			@current_sections
		end
	end

	def execute_command(command_line, layer)
		@command_line = command_line
		command, foo, string = @command_line.strip.partition(' ')
		parameters = string.parse_parameters
		properties = @graph.conf.layer_attributes[layer] || {}

		case command
		when 'n' # new node
			sentence_set?
			log_step = @log.add_step(:command => @command_line)
			layer = set_new_layer(parameters[:words], properties)
			properties.merge!(extract_attributes(parameters))
			sentence = if ref_node_reference = parameters[:all_nodes][0]
				element_by_identifier(ref_node_reference).sentence
			else
				@current_sections.first.sentence_nodes.first
			end
			@graph.add_anno_node(
				:attr => properties,
				:sentence => sentence,
				:log => log_step
			)

		when 'e' # new edge
			sentence_set?
			log_step = @log.add_step(:command => @command_line)
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
			log_step = @log.add_step(:command => @command_line)
			@graph.conf.layers.map(&:attr).each do |a|
				properties.delete(a)
			end
			layer = set_new_layer(parameters[:words], properties)
			elements = extract_elements(parameters[:elements])
			# sentence and section nodes may be annotated with arbitrary key-value pairs
			elements.of_type('s', 'p').each do |element|
				element.annotate(parameters[:attributes], log_step)
			end
			# annotation of annotation nodes and edges and token nodes is restricted by tagset
			unless (anno_elements = elements.of_type('a', 't')).empty?
				annotations = properties.merge(extract_attributes(parameters))
				anno_elements.each{|e| e.annotate(annotations, log_step)}
			end
			undefined_references?(parameters[:elements])

		when 'd' # delete elements
			sentence_set?
			log_step = @log.add_step(:command => @command_line)
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
			log_step = @log.add_step(:command => @command_line)
			layer = set_new_layer(parameters[:words], properties)
			@graph.add_parent_node(
				extract_elements(parameters[:all_nodes]),
				properties.merge(extract_attributes(parameters)),
				properties.clone,
				log_step
			)
			undefined_references?(parameters[:all_nodes])

		when 'c', 'h' # attach new child node
			sentence_set?
			log_step = @log.add_step(:command => @command_line)
			layer = set_new_layer(parameters[:words], properties)
			@graph.add_child_node(
				extract_elements(parameters[:all_nodes]),
				properties.merge(extract_attributes(parameters)),
				properties.clone,
				log_step
			)
			undefined_references?(parameters[:all_nodes])

		when 'ni' # build node and "insert in edge"
			sentence_set?
			log_step = @log.add_step(:command => @command_line)
			layer = set_new_layer(parameters[:words], properties)
			properties.merge!(extract_attributes(parameters))
			extract_elements(parameters[:edges]).each do |edge|
				@graph.insert_node(edge, properties, log_step)
			end
			undefined_references?(parameters[:edges])

		when 'di', 'do' # remove node and connect parent/child nodes
			sentence_set?
			log_step = @log.add_step(:command => @command_line)
			layer = set_new_layer(parameters[:words], properties)
			extract_elements(parameters[:nodes]).each do |node|
				@graph.delete_and_join(node, command == 'di' ? :in : :out, log_step)
			end
			undefined_references?(parameters[:nodes])

		when 'ns' # create and append new sentence(s)
			raise 'Please specify a name!' if parameters[:words] == []
			log_step = @log.add_step(:command => @command_line)
			current_sentence = @current_sections ? @current_sections.last.sentence_nodes.last : nil
			new_nodes = @graph.insert_sentences(current_sentence, parameters[:words], log_step)
			@current_sections = [new_nodes.first]

		when 't' # build tokens and append them
			sentence_set?
			log_step = @log.add_step(:command => @command_line)
			@graph.build_tokens(parameters[:words], :sentence => @current_sections.last, :log => log_step)

		when 'tb', 'ti' # build tokens and insert them before given token
			sentence_set?
			log_step = @log.add_step(:command => @command_line)
			undefined_references?(parameters[:tokens][0..0])
			node = element_by_identifier(parameters[:tokens][0])
			@graph.build_tokens(parameters[:words][1..-1], :next_token => node, :log => log_step)

		when 'ta' # build tokens and insert them after given token
			sentence_set?
			log_step = @log.add_step(:command => @command_line)
			undefined_references?(parameters[:tokens][0..0])
			node = element_by_identifier(parameters[:tokens][0])
			@graph.build_tokens(parameters[:words][1..-1], :last_token => node, :log => log_step)

		when 'undo', 'z'
			@log.undo
			reset_current_sections

		when 'redo', 'y'
			@log.redo
			reset_current_sections

		when 's' # change sentence
			@current_sections = chosen_sections(parameters[:words], parameters[:name_sequences], false)

		when 'user', 'annotator'
			@log.user = @graph.set_annotator(:name => parameters[:string])

		when 's-new' # create new section as parent of other sections
			section_nodes = chosen_sections(parameters[:words], parameters[:name_sequences])
			raise 'Please specify the sections to be grouped!' if section_nodes.empty?
			log_step = @log.add_step(:command => @command_line)
			new_section = @graph.build_section(section_nodes, log_step)
			new_section.annotate(parameters[:attributes], log_step)

		when 's-rem' # remove section nodes without deleting descendant nodes
			sections = chosen_sections(parameters[:words], parameters[:name_sequences])
			log_step = @log.add_step(:command => @command_line)
			old_current_sections = @current_sections
			@current_sections = @current_sections.map(&:sentence_nodes).flatten if @current_sections & sections != []
			begin
				@graph.remove_sections(sections, log_step)
			rescue StandardError => e
				@current_sections = old_current_sections
				raise e
			end

		when 's-add' # add section(s) to existing section
			parent = chosen_sections(parameters[:words][0..0], [])[0]
			sections = chosen_sections(parameters[:words][1..-1], parameters[:name_sequences])
			log_step = @log.add_step(:command => @command_line)
			@graph.add_sections(parent, sections, log_step)

		when 's-det' # detach section(s) from existing section
			sections = chosen_sections(parameters[:words], parameters[:name_sequences])
			log_step = @log.add_step(:command => @command_line)
			@graph.detach_sections(sections)

		when 's-del', 'del' # delete section(s)
			sections = chosen_sections(parameters[:words], parameters[:name_sequences])
			log_step = @log.add_step(:command => @command_line)
			# change to next section
			old_current_sections = @current_sections
			if (@current_sections = @current_sections - sections).empty?
				current_level_sections_to_be_deleted = old_current_sections.first.same_level_sections & sections
				@current_sections = [
					current_level_sections_to_be_deleted.last.sentence_nodes.last.node_after ||
						current_level_sections_to_be_deleted.first.sentence_nodes.first.node_before
				].compact
			end
			# delete
			begin
				@graph.delete_sections(sections, log_step)
			rescue StandardError => e
				@current_sections = old_current_sections
				raise e
			end

		when 'load' # clear workspace and load corpus file
			clear_workspace
			data = @graph.read_json_file(file_path(parameters[:words][0]))
			@graph_file.replace(file_path(parameters[:words][0]))
			if @graph.file_settings[:separate_log]
				begin
					@log = Log.new_from_file(@graph, @graph_file.sub(/.json$/, '.log.json'))
				rescue
					@log = Log.new(@graph, nil, data['log'])
				end
			else
				@log = Log.new(@graph, nil, data['log'])
			end
			@windows.merge!(data['windows'].to_h) if @graph.file_settings[:save_windows]
			sentence_nodes = @graph.sentence_nodes
			@current_sections = [sentence_nodes.select{|n| n.name == @current_sections.first.name}[0]] if @current_sections
			@current_sections = [sentence_nodes.first] unless @current_sections

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
			additional = {}
			additional.merge!(:log => @log) if @graph.file_settings[:save_log] && !@graph.file_settings[:separate_log]
			additional.merge!(:windows => @windows) if @graph.file_settings[:save_windows]
			@graph.write_json_file(@graph_file, @graph.file_settings[:compact], additional)
			if @graph.file_settings[:separate_log]
				@log.write_json_file(@graph_file.sub(/.json$/, '.log.json'), @graph.file_settings[:compact])
			end

		when 'clear' # clear workspace
			clear_workspace

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
		puts "Generating graph for section(s) \"#{@current_sections.map(&:name).join(', ')}\"..." if @current_sections
		satzinfo = {:textline => '', :meta => ''}

		@tokens     = @current_sections ? @current_sections.map(&:sentence_tokens).flatten(1) : []
		all_nodes   = @current_sections ? @current_sections.map(&:nodes).flatten(1) : []
		@nodes      = all_nodes.reject{|n| n.type == 't'}
		all_edges   = all_nodes.map{|n| n.in + n.out}.flatten.uniq
		@edges      = all_edges.of_type('a')
		order_edges = all_edges.of_type('o')

		if @filter[:mode] == 'filter'
			@nodes.select!{|n| @filter[:show] == n.fulfil?(@filter[:cond])}
			@edges.select!{|e| @filter[:show] == e.fulfil?(@filter[:cond])}
		end

		satzinfo[:meta] = if @current_sections && @current_sections.length == 1
			build_label(@current_sections.first)
		else
			''
		end

		graph_options = {
			:type => :digraph,
			:rankdir => :TB,
			:use => :dot,
			:ranksep => 0.3
		}.merge(@graph.conf.xlabel ? {:forcelabels => true, :ranksep => 0.85} : {})
		viz_graph = DotGraph.new(:G, graph_options)
		token_graph = viz_graph.subgraph(:rank => :same)
		layer_graphs = {}
		@graph.conf.combinations.each do |c|
			layer_graphs[c.attr] = c.weight < 0 ? viz_graph.subgraph(:rank => :same) : viz_graph.subgraph
		end
		@graph.conf.layers.each do |l|
			layer_graphs[l.attr] = l.weight < 0 ? viz_graph.subgraph(:rank => :same) : viz_graph.subgraph
		end
		# speaker subgraphs
		if (speakers = @graph.speaker_nodes.select{|sp| @tokens.map(&:speaker).include?(sp)}) != []
			speaker_graphs = Hash[speakers.map{|s| [s, viz_graph.subgraph(:rank => :same)]}]
			# induce speaker labels and layering of speaker graphs:
			gv_speaker_nodes = []
			speaker_graphs.each do |speaker_node, speaker_graph|
				gv_speaker_nodes << speaker_graph.add_nodes(
					's' + speaker_node.id.to_s,
					{:shape => :plaintext, :label => speaker_node['name'], :fontname => @graph.conf.font}
				)
				viz_graph.add_edges(gv_speaker_nodes[-2], gv_speaker_nodes[-1], {:style => :invis}) if gv_speaker_nodes.length > 1
			end
			timeline_graph = viz_graph.subgraph(:rank => :same)
			gv_anchor = timeline_graph.add_nodes('anchor', {:style => :invis})
			viz_graph.add_edges(gv_speaker_nodes[-1], gv_anchor, {:style => :invis})
		end

		@tokens.each_with_index do |token, i|
			options = {
				:fontname => @graph.conf.font,
				:label => HTMLEntities.new.encode(build_label(token, @show_refs ? i : nil), :hexadecimal),
				:shape => :box,
				:style => :bold,
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
				token_graph.add_nodes(token, options)
			else
				# create token and point on timeline:
				gv_token = speaker_graphs[token.speaker].add_nodes(token, options)
				gv_time  = timeline_graph.add_nodes('t' + token.id.to_s, {:shape => 'plaintext', :label => "#{token.start}\n#{token.end}", :fontname => @graph.conf.font})
				# add ordering edge from speaker to speaker's first token
				viz_graph.add_edges('s' + token.speaker.id.to_s, gv_token, {:style => :invis}) if i == 0
				# multiple lines between token and point on timeline in order to force correct order:
				viz_graph.add_edges(gv_token, gv_time, {:weight => 9999, :style => :invis})
				viz_graph.add_edges(gv_token, gv_time, {:arrowhead => :none, :weight => 9999})
				viz_graph.add_edges(gv_token, gv_time, {:weight => 9999, :style => :invis})
				# order points on timeline:
				if i > 0
					viz_graph.add_edges('t' + @tokens[i-1].id.to_s, gv_time, {:arrowhead => :none})
				else
					viz_graph.add_edges(gv_anchor, gv_time, {:style => :invis})
				end
			end
		end

		@nodes.each_with_index do |node, i|
			options = {
				:fontname => @graph.conf.font,
				:color => @graph.conf.default_color,
				:shape => :box,
				:label => HTMLEntities.new.encode(build_label(node, @show_refs ? i : nil), :hexadecimal),
			}
			actual_layer_graph = nil
			if @filter[:mode] == 'hide' and @filter[:show] != node.fulfil?(@filter[:cond])
				options[:color] = @graph.conf.filtered_color
			else
				@graph.conf.layers.each do |l|
					if node[l.attr] == 't'
						options[:color] = l.color
						actual_layer_graph = layer_graphs[l.attr]
					end
				end
				@graph.conf.combinations.sort{|a,b| a.attr.length <=> b.attr.length}.each do |c|
					if c.attr.all?{|a| node[a] == 't'}
						options[:color] = c.color
						actual_layer_graph = layer_graphs[c.attr]
					end
				end
			end
			options[:fontcolor] = options[:color]
			if @found && @found[:all_nodes].include?(node)
				options[:color] = @graph.conf.found_color
				options[:penwidth] = 2
			end
			viz_graph.add_nodes(node, options)
			actual_layer_graph.add_nodes(node) if actual_layer_graph
		end

		@edges.each_with_index do |edge, i|
			label = HTMLEntities.new.encode(build_label(edge, @show_refs ? i : nil), :hexadecimal)
			options = {
				:fontname => @graph.conf.font,
				:color => @graph.conf.default_color,
				:weight => @graph.conf.edge_weight,
				:constraint => true
			}.merge(
				@graph.conf.xlabel ? {:xlabel => label} : {:label => label}
			)
			if @filter[:mode] == 'hide' and @filter[:show] != edge.fulfil?(@filter[:cond])
				options[:color] = @graph.conf.filtered_color
			else
				@graph.conf.layers.each do |l|
					if edge[l.attr] == 't'
						options[:color] = l.color
						if l.weight == 0
							options[:constraint] = false
						else
							options[:weight] = l.weight
							options[:constraint] = true
						end
					end
				end
				@graph.conf.combinations.sort{|a,b| a.attr.length <=> b.attr.length}.each do |c|
					if c.attr.all?{|a| edge[a] == 't'}
						options[:color] = c.color
						if c.weight == 0
							options[:constraint] = false
						else
							options[:weight] = c.weight
							options[:constraint] = true
						end
					end
				end
			end
			options[:fontcolor] = options[:color]
			if @found && @found[:all_edges].include?(edge)
				options[:color] = @graph.conf.found_color
				options[:penwidth] = 2
			end
			viz_graph.add_edges(edge.start, edge.end, options)
		end

		order_edges.each do |edge|
			viz_graph.add_edges(edge.start, edge.end, :style => :invis, :weight => 100)
		end

		return satzinfo.merge(:dot => viz_graph.to_s)
	end

	def sentence_set?
		if @current_sections
			return true
		else
			raise 'Create a sentence first!'
		end
	end

	def reset_current_sections
		@current_sections = [@graph.sentence_nodes.first] unless @current_sections - @graph.sentence_nodes == []
	end

	def set_cmd_cookies
		set_cookie('traw_layer', @sinatra.params[:layer]) if @sinatra.params[:layer]
		set_cookie('traw_cmd', @sinatra.params[:txtcmd]) if @sinatra.params[:txtcmd]
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
			@section_list[s][:found] = true
		end
	end

	def set_sections(h = {})
		@sections = @graph.section_structure.map do |level|
			level.map{|s| s.merge(:id => s[:node].id, :name => s[:node].name, :found => false).except(:node)}
		end
		@section_list = Hash[@sections.flatten.map{|s| [s[:id], s]}]
		set_found_sentences if !h[:clear] and @found
		@sections
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
		return result.empty? ? true : result
	end
end
