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

module Autocomplete
	def get_tagset_suggestions
		input = @sinatra.params[:word]
		suggestion_set = @sinatra.params[:suggestionSet]
		(
			@graph.tagset.for_autocomplete + autocomplete_data[suggestion_set.to_sym]
		).select do |suggestion|
			suggestion.start_with?(input)
		end.to_json
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

	private

	def autocomplete_data
		makros = @preferences[:makro] ? @graph.anno_makros.keys : []
		layers = @preferences[:makro] ? @graph.conf.layers_by_shortcut.keys : []
		tokens = @preferences[:ref] ? @view.tokens.map.with_index{|t, i| "t#{i}"} : []
		nnodes = @preferences[:ref] ? @view.dependent_nodes.map.with_index{|n, i| "n#{i}"} : []
		inodes = @preferences[:ref] ? @view.i_nodes.map.with_index{|n, i| "i#{i}"} : []
		nodes  = nnodes + inodes
		edges  = @preferences[:ref] ? @view.edges.map.with_index{|e, i| "e#{i}"} : []
		refs   = @preferences[:ref] ? tokens + nodes + edges : []
		srefs  = (sections = @graph.sections_hierarchy(@current_sections)) ? sections.map.with_index{|s, i| "s#{i}"} : []
		arefs  = @preferences[:ref] ? refs + srefs : []
		sects  = @preferences[:sect] ? @graph.section_nodes.map(&:name).compact : []
		antors = @graph.annotators.map(&:name)
		cmnds  = @preferences[:command] ? autocomplete_commands.keys : []
		{
			:anno => makros + layers + arefs,
			:nodes_anno => makros + layers + nodes + tokens,
			:edges_anno => makros + layers + edges,
			:nodes => nodes,
			:nnodes => nnodes,
			:inodes => inodes,
			:tokens => tokens,
			:ref => refs,
			:layer => layers + refs,
			:sect => sects,
			:annotator => antors,
			:command => cmnds,
			:commands => autocomplete_commands,
		}
	end

	def autocomplete_commands
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
			# :export => nil,
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
end
