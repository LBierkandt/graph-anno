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
require_relative 'log.rb'
require_relative 'graph_view.rb'
require_relative 'search_result.rb'

class GraphController
	attr_writer :sinatra
	attr_reader :graph, :log, :search_result, :current_sections

	def initialize
		@graph = Graph.new
		@log = Log.new(@graph)
		@data_table = nil
		@section_index = {}
		@sections = []
		@current_sections = nil
		@view = GraphView.new(self)
		@search_result = SearchResult.new
		@windows = {}
		@preferences = File::open('conf/preferences.yml'){|f| YAML::load(f)}
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
		section_settings_and_graph.merge(
			:sections_changed => true
		).to_json
	end

	def toggle_refs
		@view.show_refs = !@view.show_refs
		return @view.generate.merge(
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
			value = {}
		end
		return value.to_json if value[:modal]
		return section_settings_and_graph(value[:reload_sections]).merge(
			:graph_file => @graph.path.to_s,
			:current_annotator => @graph.current_annotator ? @graph.current_annotator.name : '',
			:command => value[:command],
			:windows => @windows,
			:messages => @cmd_error_messages
		).to_json
	end

	def change_sentence
		set_section(@sinatra.params[:sentence])
		return @view.generate.merge(
			:autocomplete => autocomplete_data,
			:sections_changed => true
		).to_json
	end

	def set_filter
		set_filter_cookies
		mode = @sinatra.params[:mode].partition(' ')
		@view.filter = {:cond => @graph.parse_attributes(@sinatra.params[:filter])[:op], :mode => mode[0], :show => (mode[2] == 'rest')}
		return @view.generate.merge(
			:sections_changed => false
		).to_json
	end

	def search
		set_cookie('traw_query', @sinatra.params[:query])
		begin
			@search_result.set(@graph.teilgraph_suchen(@sinatra.params[:query]))
		rescue StandardError => e
			@search_result.error(error_message_html(e.message))
		end
		@section_index.each{|id, h| h[:found] = false}
		set_found_sections
		return @view.generate.merge(
			:sections => @sections,
			:current_sections => current_section_ids,
			:search_result => @search_result.text,
			:sections_changed => false
		).to_json
	end

	def clear_search
		@search_result.reset
		return @view.generate.merge(
			:sections => set_sections,
			:search_result => @search_result.text,
			:sections_changed => false
		).to_json
	end

	['config', 'metadata', 'makros', 'tagset', 'speakers', 'annotators', 'file', 'pref'].each do |form_name|
		define_method("#{form_name}_form") do
			@sinatra.haml(
				:"#{form_name}_form",
				:locals => {
					:preferences => @preferences,
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
			@graph.conf = GraphConf.new(
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
		return {:autocomplete => autocomplete_data}.to_json
	end

	def save_file
		@graph.file_settings.clear
		[:compact, :save_log, :separate_log, :save_windows].each do |property|
			@graph.file_settings[property] = !!@sinatra.params[property.to_s]
		end
		return true.to_json
	end

	def save_pref
		[:autocompletion, :command, :file, :sect, :anno, :makro, :ref, :annotator].each do |property|
			@preferences[property] = !!@sinatra.params[property.to_s]
		end
		File::open('conf/preferences.yml', 'w'){|f| f.write(YAML::dump(@preferences))}
		return {
			:preferences => @preferences,
			:autocomplete => autocomplete_data,
		}.to_json
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
		set_sections
		@current_sections = [@graph.nodes[@section_index.keys.first]]
		return {
			:current_sections => current_section_ids,
			:sections => @sections,
			:current_annotator => @graph.current_annotator ? @graph.current_annotator.name : ''
		}.to_json
	end

	def export_subcorpus(filename)
		if @search_result.valid?
			subgraph = @graph.subcorpus(@section_index.values.select{|s| s[:found]}.map{|s| @graph.nodes[s[:id]]})
			@sinatra.headers("Content-Type" => "data:Application/octet-stream; charset=utf8")
			return JSON.pretty_generate(subgraph, :indent => ' ', :space => '').encode('UTF-8')
		end
	end

	def export_data
		return error_message_html('Execute a search first!') unless @search_result.valid?
		begin
			anfrage = @sinatra.params[:query]
			@data_table = @graph.teilgraph_ausgeben(@search_result, anfrage, :string)
			return ''
		rescue StandardError => e
			return error_message_html(e.message)
		end
	end

	def export_data_table(filename)
		if @data_table
			@sinatra.headers("Content-Type" => "data:Application/octet-stream; charset=utf8")
			return @data_table
		end
	end

	def annotate_query
		return {:search_result => error_message_html('Execute a search first!')}.to_json unless @search_result.valid?
		begin
			search_result_preserved = @graph.teilgraph_annotieren(@search_result, @sinatra.params[:query])
		rescue StandardError => e
			return {:search_result => error_message_html(e.message)}.to_json
		end
		@search_result.reset unless search_result_preserved
		return @view.generate.merge(
			:sections => set_sections,
			:search_result => @search_result.text,
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

	def get_file_list
		input = @sinatra.params[:input]
		relative = input[0] != '/'
		Dir.glob("#{'data/' if relative}#{input}*").map{|file|
			if File.directory?(file)
				file.sub!(/^data\//, '') if relative
				# strip path and add trailing slash
				file.sub(/^.*\/([^\/]+)$/, '\1') + '/'
			else
				# exclude non-json and log files, strip path
				(file.match(/\.json$/) && !file.match(/\.log\.json$/)) ? file.sub(/^(.+\/)?([^\/]+)$/, '\2') : nil
			end
		}.compact.to_json
	end

	def documentation(filename)
		@sinatra.send_file('doc/' + filename)
	end

	private

	def current_section_ids
		@current_sections.map{|section| section.id.to_s}
	end

	def clear_workspace
		@graph.clear
		@search_result.reset
		@current_sections = nil
		@log = Log.new(@graph)
	end

	def section_settings_and_graph(reload_sections = true)
		@view.generate.merge(
			:autocomplete => autocomplete_data,
			:preferences => @preferences,
			:current_sections => @current_sections ? current_section_ids : nil,
			:sections_changed => (@current_sections && @sinatra.params[:sections] && @sinatra.params[:sections] == current_section_ids) ? false : true
		).merge(
			reload_sections ? {:sections => set_sections} : {:update_sections => update_sections}
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

	def sectioning_info(node)
		{:id => node.id, :name => node.name, :text => node.text}
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
			'n' => @view.nodes[i],
			'e' => @view.edges[i],
			't' => @view.tokens[i],
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
		reload_sections = false

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
			extract_elements(parameters[:all_nodes] + parameters[:edges]).each do |element|
				element.delete(:log => log_step, :join => true)
			end
			undefined_references?(parameters[:elements])

		when 'l' # set current layer and layer of elements
			log_step = @log.add_step(:command => @command_line)
			layer = set_new_layer(parameters[:words], properties)
			annotations = Hash[@graph.conf.layers.map{|l| [l.attr, nil]}].merge(properties)
			extract_elements(parameters[:all_nodes] + parameters[:edges]).each do |e|
				e.annotate(annotations, log_step)
			end
			undefined_references?(parameters[:elements])

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
			reload_sections = true

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
			reload_sections = true

		when 'redo', 'y'
			@log.redo
			reset_current_sections
			reload_sections = true

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
			reload_sections = true

		when 's-rem' # remove section nodes without deleting descendant nodes
			sections = chosen_sections(parameters[:words], parameters[:name_sequences])
			log_step = @log.add_step(:command => @command_line)
			old_current_sections = @current_sections
			@current_sections = @current_sections.map(&:sentence_nodes).flatten if @current_sections & sections != []
			begin
				@graph.remove_sections(sections, log_step)
				reload_sections = true
			rescue StandardError => e
				@current_sections = old_current_sections
				raise e
			end

		when 's-add' # add section(s) to existing section
			parent = chosen_sections(parameters[:words][0..0], [])[0]
			sections = chosen_sections(parameters[:words][1..-1], parameters[:name_sequences])
			log_step = @log.add_step(:command => @command_line)
			@graph.add_sections(parent, sections, log_step)
			reload_sections = true

		when 's-det' # detach section(s) from existing section
			sections = chosen_sections(parameters[:words], parameters[:name_sequences])
			log_step = @log.add_step(:command => @command_line)
			@graph.detach_sections(sections)
			reload_sections = true

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
				reload_sections = true
			rescue StandardError => e
				@current_sections = old_current_sections
				raise e
			end

		when 'load' # clear workspace and load corpus file
			raise 'Please specify a file name!' unless parameters[:words][0]
			clear_workspace
			data = @graph.read_json_file(file_path(parameters[:words][0]))
			if @graph.file_settings[:separate_log]
				begin
					@log = Log.new_from_file(@graph, @graph.path.sub(/\.json$/, '.log.json'))
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
			reload_sections = true

		when 'append', 'add' # load corpus file and append it to the workspace
			raise 'Please specify a file name!' unless parameters[:words][0]
			@graph.add_file(file_path(parameters[:words][0]))
			@search_result.reset
			reload_sections = true

		when 'save' # save workspace to corpus file
			path = @graph.path || parameters[:words][0]
			raise 'Please specify a file name!' unless path
			additional = {}
			additional.merge!(:log => @log) if @graph.file_settings[:save_log] && !@graph.file_settings[:separate_log]
			additional.merge!(:windows => @windows) if @graph.file_settings[:save_windows]
			@graph.write_json_file(path, additional)
			if @graph.file_settings[:separate_log]
				@log.write_json_file(path.sub(/\.json$/, '.log.json'), @graph.file_settings[:compact])
			end

		when 'clear' # clear workspace
			clear_workspace
			reload_sections = true

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

		when 'config', 'tagset', 'metadata', 'makros', 'speakers', 'annotators', 'file', 'pref'
			return {:modal => command}

		when ''
		else
			raise "Unknown command \"#{command}\""
		end
		return {:command => command, :reload_sections => reload_sections}
	end

	def sentence_set?
		return true if @current_sections
		raise 'Create a sentence first!'
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

	def set_found_sections
		@search_result.sections.each{|s| @section_index[s.id][:found] = true}
	end

	def set_sections
		@sections = @graph.section_structure.map do |level|
			level.map{|s| s.merge(sectioning_info(s[:node])).merge(:found => false).except(:node)}
		end
		@section_index = Hash[@sections.flatten.map{|s| [s[:id], s]}]
		set_found_sections if @search_result.valid?
		@sections
	end

	def update_sections
		sections = (@graph.sections_hierarchy(@current_sections) || []).flatten
		section_info = sections.map{|s| sectioning_info(s)}
		section_info.each{|s| @section_index[s[:id]].merge!(s)}
		section_info
	end

	def undefined_references?(ids)
		undefined_ids = ids.select{|id| !element_by_identifier(id)}
		@cmd_error_messages << "Undefined element(s): #{undefined_ids * ', '}" unless undefined_ids.empty?
	end

	def file_path(input)
		(input[0] == '/' ? '' : 'data/') + input + (input.match(/\.json$/) ? '' : '.json')
	end

	def autocomplete_data
		commands = {
			:a => :aanno,
			:n => :anno,
			:e => :anno,
			:p => :anno,
			:g => :anno,
			:c => :anno,
			:h => :anno,
			:ni => :anno,
			:di => :anno,
			:do => :anno,
			:d => :ref,
			:t => nil,
			:tb => nil,
			:ta => nil,
			:undo => nil,
			:z => nil,
			:redo => nil,
			:y => nil,
			:l => :layer,
			:annotator => :annotator,
			:user => :annotator,
			:ns => nil,
			:'s-new' => :sect,
			:'s-rem' => :sect,
			:'s-add' => :sect,
			:'s-det' => :sect,
			:'s-del' => :sect,
			:load => :file,
			:add => :file,
			:append => :file,
			:save => nil,
			:clear => nil,
			:s => :sect,
			:image => nil,
			:export => nil,
			:import => nil,
			:config => nil,
			:tagset => nil,
			:makros => nil,
			:metadata => nil,
			:annotators => nil,
			:file => nil,
			:pref => nil,
			:'' => :command
		}
		tagset = @preferences[:anno] ? @graph.tagset.for_autocomplete : []
		makros = @preferences[:makro] ? @graph.layer_makros.merge(@graph.anno_makros).keys : []
		layers = @preferences[:makro] ? @graph.layer_makros.keys : []
		refs   = @preferences[:ref] ? @view.tokens.map.with_index{|t, i| "t#{i}"} + @view.nodes.map.with_index{|n, i| "n#{i}"} + @view.edges.map.with_index{|e, i| "e#{i}"} : []
		srefs  = (sections = @graph.sections_hierarchy(@current_sections)) ? sections.map.with_index{|s, i| "s#{i}"} : []
		arefs  = @preferences[:ref] ? refs + srefs : []
		sects  = @preferences[:sect] ? @graph.section_nodes.map(&:name).compact : []
		antors = @graph.annotators.map(&:name)
		cmnds  = @preferences[:command] ? commands.keys : []
		{
			:anno => tagset + makros + refs,
			:aanno => tagset + makros + arefs,
			:ref => refs,
			:layer => layers + refs,
			:sect => sects,
			:annotator => antors,
			:command => cmnds,
			:commands => commands,
		}
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
