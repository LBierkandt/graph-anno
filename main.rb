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

require 'sinatra'
require 'haml'

require './lib/anno_graph'
require './lib/expansion_module'
require './lib/graph_display'
require './lib/graph_controller'

controller = GraphController.new

get '/' do
	controller.set_vars(params, request, response)
	controller.root(self)
end

get '/graph' do
	controller.set_vars(params, request, response)
	controller.draw_graph
end

get '/toggle_refs' do
	controller.set_vars(params, request, response)
	controller.toggle_refs
end

post '/commandline' do
	controller.set_vars(params, request, response)
	controller.handle_commandline
end

post '/sentence' do
	controller.set_vars(params, request, response)
	controller.change_sentence
end

post '/filter' do
	controller.set_vars(params, request, response)
	controller.filter
end

post '/search' do
	controller.set_vars(params, request, response)
	controller.search
end

get '/export/subcorpus.json' do
	controller.set_vars(params, request, response)
	controller.export_subcorpus
end

get '/export_data' do
	controller.set_vars(params, request, response)
	controller.export_data
end

get '/export/data_table.csv' do
	controller.set_vars(params, request, response)
	controller.export_data_table
end

get '/doc/:filename' do
	headers "Content-Type" => "data:Application/octet-stream; charset=utf8"
	send_file 'doc/' + params[:filename]
end