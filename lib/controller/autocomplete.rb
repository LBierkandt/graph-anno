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

module Autocomplete
	def get_autocomplete_suggestions
		input = @sinatra.params[:word]
		data = case @sinatra.params[:suggestionSet].to_sym
		when :file
			return file_suggestions(input).to_json
		when :anno
			tagset_suggestions(@sinatra.params) + makro_suggestions + aref_suggestions
		when :nodes_anno
			tagset_suggestions(@sinatra.params) + makro_suggestions + layer_suggestions +
				nnode_suggestions + inode_suggestions + token_suggestions
		when :edges_anno
			tagset_suggestions(@sinatra.params) + makro_suggestions + layer_suggestions + edge_suggestions
		when :nodes
			nnode_suggestions + inode_suggestions
		when :nnodes
			nnode_suggestions
		when :inodes
			inode_suggestions
		when :tokens
			token_suggestions
		when :ref
			ref_suggestions
		when :layer
			layer_suggestions + ref_suggestions
		when :sect
			section_suggestions
		when :annotator
			annotator_suggestions
		when :command
			command_suggestions
		end
		data.select do |suggestion|
			suggestion.to_s.start_with?(input)
		end.to_json
	end

	private

	def self.commands
		{
			:a => :anno,
			:n => :nodes_anno,
			:e => :nodes_anno,
			:p => :nodes_anno,
			:g => :nodes_anno,
			:c => :nodes_anno,
			:h => :nodes_anno,
			:ni => :edges_anno,
			:di => :nodes,
			:do => :nodes,
			:sa => :inodes,
			:sd => :nnodes,
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
			:play => :tokens,
			:config => nil,
			:tagset => nil,
			:makros => nil,
			:metadata => nil,
			:annotators => nil,
			:file => nil,
			:pref => nil,
			:'' => :command
		}
	end

	def tagset_suggestions(params)
		parameters = params[:before].parse_parameters
		if params[:suggestionSet] == 'anno'
			@graph.tagset.for_autocomplete(
				extract_elements(parameters[:elements])
			)
		else
			layers = if layer_shortcut = get_layer_shortcut(parameters[:words])
				@graph.conf.layer_by_shortcut[layer_shortcut]
			else
				@graph.conf.layer_by_shortcut[params[:layer]]
			end
			element = if params[:command] == 'e'
				@graph.create_phantom_edge(:type => 'a', :layers => layers)
			else
				@graph.create_phantom_node(:type => 'a', :layers => layers)
			end
			@graph.tagset.for_autocomplete([element])
		end
	end

	def file_suggestions(input)
		relative = input[0] != '/'
		Dir.glob("#{'data/' if relative}#{input}*").map{|file|
			if File.directory?(file)
				file.sub!(/^data\//, '') if relative
				# strip path and add trailing slash
				file.sub(/^.*\/([^\/]+)$/, '\1') + '/'
			else
				# exclude non-json and log files, strip path
				(file.match(/\.json$/) && !file.match(/log\.json$/)) ? file.sub(/^(.+\/)?([^\/]+)$/, '\2') : nil
			end
		}.compact
	end

	def makro_suggestions
		@preferences[:makro] ? @graph.anno_makros.keys : []
	end

	def layer_suggestions
		@preferences[:makro] ? @graph.conf.layer_by_shortcut.keys : []
	end

	def token_suggestions
		@preferences[:ref] ? @view.tokens.map.with_index{|t, i| "t#{i}"} : []
	end

	def nnode_suggestions
		@preferences[:ref] ? @view.dependent_nodes.map.with_index{|n, i| "n#{i}"} : []
	end

	def inode_suggestions
		@preferences[:ref] ? @view.i_nodes.map.with_index{|n, i| "i#{i}"} : []
	end

	def edge_suggestions
		@preferences[:ref] ? @view.edges.map.with_index{|e, i| "e#{i}"} : []
	end

	def ref_suggestions
		token_suggestions + nnode_suggestions + inode_suggestions + edge_suggestions
	end

	def sref_suggestions
		(sections = @graph.sections_hierarchy(@current_sections)) ? sections.map.with_index{|s, i| "s#{i}"} : []
	end

	def aref_suggestions
		@preferences[:ref] ? ref_suggestions + sref_suggestions : []
	end

	def section_suggestions
		@preferences[:sect] ? @graph.section_nodes.map(&:name).compact : []
	end

	def annotator_suggestions
		@graph.annotators.map(&:name)
	end

	def command_suggestions
		@preferences[:command] ? Autocomplete.commands.keys : []
	end
end
