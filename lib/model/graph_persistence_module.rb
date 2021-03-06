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

require 'pathname.rb'

module GraphPersistence
	GRAPH_FORMAT_VERSION = 11
	attr_reader :path

	# @return [Hash] the graph in hash format with version number and settings: {:nodes => [...], :edges => [...], :version => String, ...}
	def to_h(h = {})
		nodes = h[:nodes] || @nodes.values
		edges = h[:edges] || @edges.values
		additional = h[:additional] || {}
		{
			:nodes => nodes.map(&:to_h),
			:edges => edges.map(&:to_h),
			:version => GRAPH_FORMAT_VERSION,
			:conf => @conf.to_h.except(:font),
			:info => @info,
			:anno_makros => @anno_makros,
			:search_makros => @makros_plain,
			:tagset => @tagset,
			:annotators => @annotators,
			:file_settings => @file_settings,
			:media => relative_path(@media),
		}.merge(additional).compact
	end

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		self.to_h.to_json(*a)
	end

	# reads a graph JSON file into self, clearing self before
	# @param p [String] path to the JSON file
	def read_json_file(p)
		puts "Reading file #{p} ..."
		self.clear

		@path = file_path = Pathname.new(p)
		data = File.open(file_path, 'r:utf-8'){|f| JSON.parse(f.read)}
		if data['master'] # is part file
			@path = file_path.dirname + data['master']
			master_data = File.open(@path, 'r:utf-8'){|f| JSON.parse(f.read)}
			version, log_data = init_from_master(master_data).values_at(:version, :log_data)
			preprocess_raw_data(data)
			@multifile[:sentence_index][relative_path(file_path)] = add_elements(data)
		else
			version, log_data = init_from_master(data).values_at(:version, :log_data)
			if data['files']
				@multifile[:files].each do |file|
					last_sentence_node = sentence_nodes.last
					d = File.open(@path.dirname + file, 'r:utf-8'){|f| JSON.parse(f.read)}
					preprocess_raw_data(d)
					@multifile[:sentence_index][file] = add_elements(d)
					@multifile[:order_edges] << add_order_edge(:start => last_sentence_node, :end => @multifile[:sentence_index][file].first)
				end
			else
				@multifile[:files] = ['0001.json']
				@multifile[:sentence_index] = {'0001.json' => sentence_nodes}
			end
		end

		update_graph_format(version) if version < GRAPH_FORMAT_VERSION

		puts "Read #{file_path}."

		return {:graph_data => data, :log_data => log_data}
	end

	# load another part file of a partially loaded multi-file corpus
	# @param p [String] path to the part file
	def add_part_file(p)
		puts "Reading file #{p} ..."
		file_path = Pathname.new(p)
		data = File.open(file_path, 'r:utf-8'){|f| JSON.parse(f.read)}
		file = relative_path(file_path)
		raise 'File is not a part of the loaded corpus!' unless data['master'] and data['master'] == relative_path(@path, file_path)
		raise 'File is not listed as part of the loaded corpus!' unless @multifile[:files].include?(file)
		raise 'File has been loaded already!' if @multifile[:sentence_index][file]
		before, after = adjacent_sentence_nodes(file)
		edges_between(before, after).of_type('o').each do |e|
			@multifile[:order_edges].delete(e.delete)
		end
		preprocess_raw_data(data)
		@multifile[:sentence_index][file] = add_elements(data)
		@multifile[:order_edges] << add_order_edge(:start => before, :end => @multifile[:sentence_index][file].first)
		@multifile[:order_edges] << add_order_edge(:start => @multifile[:sentence_index][file].last, :end => after)
	end

	# load corpus and append it to the workspace
	# @param p [String] path to the graph file
	def append_file(p)
		puts "Reading file #{p} ..."
		file_path = Pathname.new(p)
		new_graph = Graph.new
		new_graph.read_json_file(file_path)
		self.append!(new_graph)
	end

	# serializes self in one ore multiple JSON file(s)
	# @param path [String] path to the JSON file
	# @param options [Hash] additional: data (hash) that should be added to the saved json; log: log object to be saved (or nil)
	def store(path, options = {})
		if path.is_a?(String)
			base_path = path[0] == '/' ? '' : 'data/'
			@path = Pathname.new(base_path + path) + 'master.json'
		end
		rename_part_files if @multifile[:file_renames]
		# assign elements to files
		nodes_per_file = {}
		edges_per_file = {}
		@multifile[:sentence_index].each do |file, sentences|
			nodes_per_file[file] = (sections_hierarchy(sentences) + sentences.map(&:nodes)).flatten
			edges_per_file[file] = nodes_per_file[file].map{|n| n.in + n.out}.flatten.uniq - @multifile[:order_edges]
			write_part_file(file, nodes_per_file[file], edges_per_file[file])
		end
		master_nodes = @node_index['sp'].values + @node_index['a'].values.select{|n| !n.sentence}
		master_edges = @edges.values - edges_per_file.values.flatten - @multifile[:order_edges]
		write_master_file(master_nodes, master_edges, options[:additional].to_h, path != @path)
		write_log_file(options[:log]) if options[:log]
	end

	# export corpus as SQL file for import in GraphInspect
	# @param name [String] The name of the corpus, and the name under which the file will be saved
	def export_sql(name)
		Dir.mkdir('exports/sql') unless File.exist?('exports/sql')
		# corpus
		str = "INSERT INTO `corpora` (`name`, `conf`, `makros`, `info`) VALUES\n"
		str += "('#{name.sql_json_escape_quotes}', '#{@conf.to_h.to_json.sql_json_escape_quotes}', '#{@makros_plain.to_json.sql_json_escape_quotes}', '#{@info.to_json.sql_json_escape_quotes}');\n"
		str += "SET @corpus_id := LAST_INSERT_id();\n"
		# nodes
		@nodes.values.each_slice(1000) do |chunk|
			str += "INSERT INTO `nodes` (`id`, `corpus_id`, `attr`, `type`) VALUES\n"
			str += chunk.map do |n|
				"(#{n.id}, @corpus_id, '#{n.attr.to_json.sql_json_escape_quotes}', '#{n.type}')"
			end * ",\n" + ";\n"
		end
		# edges
		@edges.values.each_slice(1000) do |chunk|
			str += "INSERT INTO `edges` (`id`, `corpus_id`, `start`, `end`, `attr`, `type`) VALUES\n"
			str += chunk.map do |e|
				"(#{e.id}, @corpus_id, '#{e.start.id}', '#{e.end.id}', '#{e.attr.to_json.sql_json_escape_quotes}', '#{e.type}')"
			end * ",\n" + ";\n"
		end
		File.open("exports/sql/#{name}.sql", 'w') do |f|
			f.write(str)
		end
	end

	# export layer configuration as JSON file for import in other graphs
	# @param name [String] The name of the file
	def export_config(name)
		Dir.mkdir('exports/config') unless File.exist?('exports/config')
		File.open("exports/config/#{name}.config.json", 'w') do |f|
			f.write(JSON.pretty_generate(@conf, :indent => ' ', :space => '').encode('UTF-8'))
		end
	end

	# export tagset as JSON file for import in other graphs
	# @param name [String] The name of the file
	def export_tagset(name)
		Dir.mkdir('exports/tagset') unless File.exist?('exports/tagset')
		File.open("exports/tagset/#{name}.tagset.json", 'w') do |f|
			f.write(JSON.pretty_generate(@tagset, :indent => ' ', :space => '').encode('UTF-8'))
		end
	end

	# export annotators as JSON file for import in other graphs
	# @param name [String] The name of the file
	def export_annotators(name)
		Dir.mkdir('exports/annotators') unless File.exist?('exports/annotators')
		File.open("exports/annotators/#{name}.annotators.json", 'w') do |f|
			f.write(JSON.pretty_generate(@annotators, :indent => ' ', :space => '').encode('UTF-8'))
		end
	end

	# loads layer configurations from JSON file
	# @param name [String] The name of the file
	def import_config(name)
		File.open("exports/config/#{name}.config.json", 'r:utf-8') do |f|
			@conf = GraphConf.new(JSON.parse(f.read))
		end
	end

	# loads allowed annotations from JSON file
	# @param name [String] The name of the file
	def import_tagset(name)
		File.open("exports/tagset/#{name}.tagset.json", 'r:utf-8') do |f|
			@tagset = Tagset.new(self, JSON.parse(f.read))
		end
	end

	# loads allowed annotations from JSON file
	# @param name [String] The name of the file
	def import_annotators(name)
		File.open("exports/annotators/#{name}.annotators.json", 'r:utf-8') do |f|
			@annotators = JSON.parse(f.read).map{|a| Annotator.new(a.symbolize_keys.merge(:graph => self))}
		end
	end

	private

	def reset_multifile(options = {})
		@multifile = {:files => [], :sentence_index => {}, :order_edges => []}
		if options[:default_file]
			@multifile[:files] = ['0001.json']
			@multifile[:sentence_index] = {'0001.json' => []}
		end
	end

	def init_from_master(data)
		reset_multifile
		@multifile[:files] = data['files']
		preprocess_raw_data(data)
		add_configuration(data)
		add_elements(data)
		log_data = if file_settings[:save_log]
			begin
				data['log'] || File.open(@path.dirname + 'log.json', 'r:utf-8'){|f| JSON.parse(f.read)}
			rescue Errno::ENOENT
				{}
			end
		end
		return {
			:version => data['version'].to_i,
			:log_data => log_data,
		}
	end

	def add_elements(data)
		@highest_node_id = [@highest_node_id, data['max_node_id'].to_i].max
		@highest_edge_id = [@highest_edge_id, data['max_edge_id'].to_i].max
		sentence_node = nil
		(data['nodes'] || []).each do |n|
			node = add_node(n.merge(:raw => true))
			sentence_node = node if node.type == 's'
		end
		(data['edges'] || []).each do |e|
			add_edge(e.merge(:raw => true))
		end
		return [] unless sentence_node
		sentence_node.ordered_sister_nodes
	end

	def add_configuration(data)
 		@annotators = (data['annotators'] || []).map{|a| Annotator.new(a.symbolize_keys.merge(:graph => self))}
		@anno_makros = (data['anno_makros'] || {}).map_hash do |key, annotations|
			if annotations.is_a?(Hash) # old format before introduction of layer-specific annotations
				annotations.map{|key, value| {:key => key, :value => value}}
			else
				annotations.map(&:symbolize_keys)
			end
		end
		@info = data['info'] || {}
		@conf = GraphConf.new(data['conf'])
		@tagset = Tagset.new(self, data['allowed_anno'] || data['tagset'])
		@file_settings = (data['file_settings'] || {}).symbolize_keys
		@media = data['media'] ? (@path.dirname + data['media']).expand_path : nil
		set_makros(data['search_makros'] || [])
	end

	def preprocess_raw_data(data)
		version = data['version'].to_i
		update_raw_graph_data(data, version) if version < GRAPH_FORMAT_VERSION
		data['nodes'] = data['nodes'].map{|n| n.symbolize_keys} if data['nodes']
		data['edges'] = data['edges'].map{|e| e.symbolize_keys} if data['edges']
	end

	def relative_path(path, base_path = @path)
		return nil unless path && base_path
		path.expand_path.relative_path_from(base_path.expand_path.dirname).to_s
	end

	def adjacent_sentence_nodes(file)
		i = @multifile[:files].index(file)
		before = @multifile[:files][0..([i-1, 0].max)].select{|f| @multifile[:sentence_index][f]}.to_a.last
		after = @multifile[:files][(i+1)..-1].select{|f| @multifile[:sentence_index][f]}.to_a.first
		return [
			@multifile[:sentence_index][before].to_a.last,
			@multifile[:sentence_index][after].to_a.first,
		]
	end

	def rename_part_files
		return unless @multifile[:file_renames]
		prefix = 'kajhgf8743qgo7gfto8743qfgo843qgf'
		@multifile[:file_renames].each do |old_filename, new_filename|
			next if old_filename == new_filename
			File.rename(@path.dirname + old_filename, @path.dirname + "#{prefix}#{old_filename}") rescue Errno::ENOENT
		end
		@multifile[:file_renames].each do |old_filename, new_filename|
			next if old_filename == new_filename
			File.rename(@path.dirname + "#{prefix}#{old_filename}", @path.dirname + new_filename) rescue Errno::ENOENT
		end
		@multifile.delete(:file_renames)
	end

	def write_json_file(path, data)
		puts "Writing file #{path}..."
		FileUtils.mkdir_p(path.dirname) unless File.exist?(path.dirname)
		json = @file_settings[:compact] ? data.to_json : JSON.pretty_generate(data, :indent => ' ', :space => '')
		File.open(path, 'w') do |file|
			file.write(json.encode('UTF-8'))
		end
		puts "Wrote #{path}."
	end

	def write_part_file(file, nodes, edges)
		file_path = Pathname.new(@path.dirname + file)
		write_json_file(
			file_path,
			{
				:version => GRAPH_FORMAT_VERSION,
				:master => relative_path(@path, file_path),
				:nodes => nodes.map(&:to_h),
				:edges => edges.map(&:to_h),
			}
		)
	end

	def write_master_file(nodes, edges, additional, new_corpus = false)
		write_json_file(
			@path,
			self.to_h(
				:nodes => nodes,
				:edges => edges,
				:additional => {
					:max_node_id => @highest_node_id,
					:max_edge_id => @highest_edge_id,
					:files => new_corpus ? @multifile[:sentence_index].keys : @multifile[:files],
				}.merge(additional)
			)
		)
	end

	def write_log_file(log)
		write_json_file(Pathname.new(@path.dirname + 'log.json'), log)
	end

	def update_raw_graph_data(data, version)
		puts 'Updating graph data ...'
		if version < 4
			data['nodes'] = data.delete('knoten')
			data['edges'] = data.delete('kanten')
		end
		if version < 10
			layer_definitions = data['conf'] || {
				'layers' => [
					{'attr' => 'f-layer', 'shortcut' => 'f'},
					{'attr' => 's-layer', 'shortcut' => 's'},
				],
				'combinations' => ['attr' => ['f-layer', 's-layer']]
			}
			layer_map = Hash[layer_definitions['layers'].map{|l| [l['attr'], l['shortcut']]}]
			layer_definitions['combinations'].each do |c|
				c['layers'] = c['attr'].map{|a| layer_map[a]}
			end
			klass = nil
			([:node] + data['nodes'].to_a + [:edge] + data['edges'].to_a).each do |el|
				klass = el and next if el.is_a?(Symbol)
				if version < 2
					if typ = el['attr'].delete('typ')
						el['attr']['cat'] = typ
					end
					if namespace = el['attr'].delete('namespace')
						el['attr']['sentence'] = namespace
					end
					el['attr'].delete('elementid')
					el['attr'].delete('edgetype')
				end
				if version < 5
					el['attr']['f-layer'] = 't' if 'y' == el['attr'].delete('f-ebene')
					el['attr']['s-layer'] = 't' if 'y' == el['attr'].delete('s-ebene')
				end
				if version < 7
					el['id'] = el.delete('ID')
					el['attr'].delete('tokenid')
					# introduce types
					if klass == :node
						if el['attr']['token']
							el['type'] = 't'
						elsif el['attr']['cat'] == 'meta'
							el['type'] = 's'
							el['attr'].delete('cat')
						else
							el['type'] = 'a'
						end
					else
						el['type'] = 'o' if el['type'] == 't'
						el['type'] = 'a' if el['type'] == 'g'
						el['attr'].delete('sentence')
					end
				end
				if version < 9
					el['id'] = el['id'].to_i
					el['start'] = el['start'].to_i if el['start'].is_a?(String)
					el['end'] = el['end'].to_i if el['end'].is_a?(String)
				end
				if version < 10 && el['attr']
					layers = layer_map.map{|attr, shortcut| ('t' == el['attr'].delete(attr)) ? shortcut : nil}.compact
					el['layers'] = layers unless layers.empty?
				end
			end
		end
	end

	def update_graph_format(version)
		if version < 7
			puts 'Updating graph format ...'
			if version < 2
				# SectNode für jeden Satz
				sect_nodes = @node_index['s'].values
				@nodes.values.map{|n| n.attr.public['sentence']}.uniq.each do |s|
					if sect_nodes.select{|k| k.attr.public['sentence'] == s}.empty?
						add_sect_node(:attr => {'sentence' => s}, :raw => true)
					end
				end
			end
			if version < 7
				# OrderEdges and SectEdges for SectNodes
				sect_nodes = @node_index['s'].values.sort_by{|n| n.attr.public['sentence']}
				sect_nodes.each_with_index do |s, i|
					add_order_edge(:start => sect_nodes[i - 1], :end => s) if i > 0
					s.name = s.attr.public.delete('sentence')
					@nodes.values.select{|n| n.attr.public['sentence'] == s.name}.each do |n|
						n.attr.public.delete('sentence')
						add_sect_edge(:start => s, :end => n)
					end
				end
			end
		end
	end
end
