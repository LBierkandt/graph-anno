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

require 'json.rb'

module GraphPersistence
	GRAPH_FORMAT_VERSION = 9

	# @return [Hash] the graph in hash format with version number and settings: {:nodes => [...], :edges => [...], :version => String, ...}
	def to_h
		{
			:nodes => @nodes.values.map(&:to_h),
			:edges => @edges.values.map(&:to_h),
			:version => GRAPH_FORMAT_VERSION,
			:conf => @conf.to_h.except(:font),
			:info => @info,
			:anno_makros => @anno_makros,
			:tagset => @tagset,
			:annotators => @annotators,
			:file_settings => @file_settings,
			:search_makros => @makros_plain,
		}
	end

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		self.to_h.to_json(*a)
	end

	# reads a graph JSON file into self, clearing self before
	# @param path [String] path to the JSON file
	def read_json_file(path)
		puts 'Reading file "' + path + '" ...'
		self.clear

		file = open(path, 'r:utf-8')
		data = JSON.parse(file.read)
		file.close
		version = data['version'].to_i
		update_raw_graph_data(data, version) if version < GRAPH_FORMAT_VERSION
		data['nodes'] = data['nodes'].map{|n| n.symbolize_keys}
		data['edges'] = data['edges'].map{|e| e.symbolize_keys}

		@annotators = (data['annotators'] || []).map{|a| Annotator.new(a.symbolize_keys.merge(:graph => self))}
		add_hash(data)
		@anno_makros = data['anno_makros'] || {}
		@info = data['info'] || {}
		@tagset = Tagset.new(data['allowed_anno'] || data['tagset'])
		@file_settings = (data['file_settings'] || {}).symbolize_keys
		@conf = AnnoGraphConf.new(data['conf'])
		create_layer_makros
		@makros_plain += data['search_makros'] || []
		@makros += parse_query(@makros_plain * "\n")['def']

		update_graph_format(version) if version < GRAPH_FORMAT_VERSION

		puts 'Read "' + path + '".'

		return data
	end

	# serializes self in a JSON file
	# @param path [String] path to the JSON file
	# @param compact [Boolean] write compact JSON?
	# @param additional [Hash] data that should be added to the saved json in the form {:key => <data_to_be_saved>}, where data_to_be_save has to be convertible to JSON
	def write_json_file(path, compact = false, additional = {})
		puts 'Writing file "' + path + '"...'
		hash = self.to_h.merge(additional)
		json = compact ? hash.to_json : JSON.pretty_generate(hash, :indent => ' ', :space => '')
		File.open(path, 'w') do |file|
			file.write(json.encode('UTF-8'))
		end
		puts 'Wrote "' + path + '".'
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
			@conf = AnnoGraphConf.new(JSON.parse(f.read))
		end
	end

	# loads allowed annotations from JSON file
	# @param name [String] The name of the file
	def import_tagset(name)
		File.open("exports/tagset/#{name}.tagset.json", 'r:utf-8') do |f|
			@tagset = Tagset.new(JSON.parse(f.read))
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

	def add_hash(h)
		h['nodes'].each do |n|
			self.add_node(n.merge(:raw => true))
		end
		h['edges'].each do |e|
			self.add_edge(e.merge(:raw => true))
		end
	end

	def update_raw_graph_data(data, version)
		if version < 4
			data['nodes'] = data.delete('knoten')
			data['edges'] = data.delete('kanten')
		end
		if version < 9
			(data['nodes'] + data['edges']).each do |el|
				el['id'] = el.delete('ID') if version < 7
				# IDs as integer
				el['id'] = el['id'].to_i
				el['start'] = el['start'].to_i if el['start'].is_a?(String)
				el['end'] = el['end'].to_i if el['end'].is_a?(String)
			end
		end
	end

	def update_graph_format(version)
		if version < 7
			puts 'Updating graph format ...'
			# Attribut 'typ' -> 'cat', 'namespace' -> 'sentence', Attribut 'elementid' entfernen
			@node_index.delete(nil)
			(@nodes.values + @edges.values).each do |k|
				if version < 2
					if k.attr.public['typ']
						k.attr.public['cat'] = k.attr.public.delete('typ')
					end
					if k.attr.public['namespace']
						k.attr.public['sentence'] = k.attr.public.delete('namespace')
					end
					k.attr.public.delete('elementid')
					k.attr.public.delete('edgetype')
				end
				if version < 5
					k.attr.public['f-layer'] = 't' if k.attr.public['f-ebene'] == 'y'
					k.attr.public['s-layer'] = 't' if k.attr.public['s-ebene'] == 'y'
					k.attr.public.delete('f-ebene')
					k.attr.public.delete('s-ebene')
				end
				if version < 7
					# introduce node types
					if k.kind_of?(Node)
						if k.token
							k.type = 't'
						elsif k.attr.public['cat'] == 'meta'
							k.type = 's'
							k.attr.public.delete('cat')
						else
							k.type = 'a'
						end
						# populate node_index
						@node_index[k.type][k.id] = k
					else
						k.type = 'o' if k.type == 't'
						k.type = 'a' if k.type == 'g'
						k.attr.public.delete('sentence')
					end
					k.attr.public.delete('tokenid')
				end
			end
			if version < 2
				# SectNode für jeden Satz
				sect_nodes = @node_index['s'].values
				@nodes.values.map{|n| n.attr.public['sentence']}.uniq.each do |s|
					if sect_nodes.select{|k| k.attr.public['sentence'] == s}.empty?
						add_node(:type => 's', :attr => {'sentence' => s}, :raw => true)
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
