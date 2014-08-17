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
require './lib/paula_exporter'
require './lib/salt_exporter'
require './lib/expansion_module'
require './lib/graph_display'
require './lib/graph_controller'

controller = GraphController.new

set :root, Dir.pwd

get '/' do
	controller.sinatra = self
	controller.root
end

get '/graph' do
	controller.sinatra = self
	controller.draw_graph
end

get '/toggle_refs' do
	controller.sinatra = self
	controller.toggle_refs
end

get '/layer_options' do
	controller.sinatra = self
	controller.layer_options
end

post '/commandline' do
	controller.sinatra = self
	controller.handle_commandline
end

post '/sentence' do
	controller.sinatra = self
	controller.change_sentence
end

post '/filter' do
	controller.sinatra = self
	controller.filter
end

post '/search' do
	controller.sinatra = self
	controller.search
end

get '/config' do
	controller.sinatra = self
	controller.config_form
end

post '/config' do
	controller.sinatra = self
	controller.save_config
end

get '/import' do
	controller.sinatra = self
	controller.import_form
end

post '/import' do
	controller.sinatra = self
	controller.import_text
end

get '/new_layer/:i' do
	controller.sinatra = self
	controller.new_layer(params[:i])
end

get '/new_combination/:i' do
	controller.sinatra = self
	controller.new_combination(params[:i])
end

get '/export/subcorpus.json' do
	controller.sinatra = self
	controller.export_subcorpus
end

get '/export_data' do
	controller.sinatra = self
	controller.export_data
end

get '/export/data_table.csv' do
	controller.sinatra = self
	controller.export_data_table
end

get '/doc/:filename' do
	send_file 'doc/' + params[:filename]
end