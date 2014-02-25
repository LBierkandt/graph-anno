# encoding: utf-8

# Copyright © 2014 Lennart Bierkandt <post@lennartbierkandt.de>
# 
# This file is part of GAST.
# 
# GAST is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# GAST is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with GAST. If not, see <http://www.gnu.org/licenses/>.

require 'sinatra'
require 'haml'

require './lib/anno_graph'
require './lib/expansion_module'
require './lib/graph_display'
require './lib/interface_methods'



graph = Anno_graph.new
display = Graph_display.new(graph)
data_table = nil
searchresult = ''
sentence_list = []
sentences_html = ''


get '/' do
	check_cookies
	haml :index, :locals => {:graph => graph, :display => display, :searchresult => searchresult}
end

get '/graph' do
	display.sentence = request.cookies['traw_sentence']
	satzinfo = display.draw_graph(:svg, 'public/graph.svg')
	{:sentence_changed => true}.update(satzinfo).to_json
end

get '/toggle_refs' do
	display.show_refs = !display.show_refs
	satzinfo = display.draw_graph(:svg, 'public/graph.svg')
	{:sentence_changed => false}.update(satzinfo).to_json
end

post '/commandline' do
	puts params[:txtcmd]
	set_cmd_cookies
	if params[:sentence] == ''
		display.sentence = nil
	else
		display.sentence = params[:sentence]
	end
	execute_command(params[:txtcmd], params[:layer], graph, display)
	response.set_cookie('traw_sentence', { :value => display.sentence, :domain => '', :path => '/', :expires => Time.now + (60 * 60 * 24 * 30) })
	satzinfo = display.draw_graph(:svg, 'public/graph.svg')
	# Prüfen, ob sich Satz geändert hat:
	if request.cookies['traw_sentence'] == display.sentence
		sentence_changed = false
	else
		sentence_changed = true
	end
	# prüfen, ob sich die Satzliste geändert hat (und nur dann neue Liste fürs select-Feld erstellen)
	if (new_sentence_list = graph.sentences) != sentence_list
		sentence_list = new_sentence_list
		sentences_html = build_sentence_html(sentence_list, graph, display.found)
	else
		sentences_html = 'none'
	end
	{:sentences_html => sentences_html, :sentence_changed => sentence_changed}.update(satzinfo).to_json
end

post '/sentence' do
	set_cmd_cookies
	display.sentence = params[:sentence]
	satzinfo = display.draw_graph(:svg, 'public/graph.svg')
	{:sentences_html => 'none', :sentence_changed => true}.update(satzinfo).to_json
end

post '/filter' do
	set_filter_cookies
	mode = params[:mode].partition(' ')
	display.filter = {:cond => params[:filter].parse_attributes[:op], :mode => mode[0], :show => (mode[2] == 'rest')}
	display.sentence = request.cookies['traw_sentence']
	satzinfo = display.draw_graph(:svg, 'public/graph.svg')
	{:sentences_html => 'none', :sentence_changed => false, :filter_applied => true}.update(satzinfo).to_json
end

post '/search' do
	set_query_cookies
	begin
		display.found = graph.teilgraph_suchen(params[:query])
		searchresult = display.found[:tg].length.to_s + ' Treffer'
	rescue StandardError => e
		display.found = {:tg => [], :id_type => {}}
		searchresult = '<span class="error_message">' + e.message.gsub("\n", '</br>') + '</span>'
	end
	display.found[:all_nodes] = display.found[:tg].map{|tg| tg.nodes}.flatten.uniq
	display.found[:all_edges] = display.found[:tg].map{|tg| tg.edges}.flatten.uniq
	display.found[:sentences] = display.found[:all_nodes].map{|k| k.sentence}.uniq
	display.sentence = request.cookies['traw_sentence']
	satzinfo = display.draw_graph(:svg, 'public/graph.svg')
	{:sentences_html => build_sentence_html(sentence_list, graph, display.found), :searchresult => searchresult, :sentence_changed => false}.update(satzinfo).to_json
end

get '/export/subcorpus.json' do
	if display.found
		subgraph = {'nodes' => [], 'edges' => []}
		display.found[:sentences].each do |sentence|
			subgraph['nodes'] += graph.nodes.values.select{|k| k.sentence == sentence}
			subgraph['edges'] += graph.edges.values.select{|k| k.sentence == sentence}
		end
		headers "Content-Type" => "data:Application/octet-stream; charset=utf8"
		JSON.pretty_generate(subgraph, :indent => ' ', :space => '').encode('UTF-8')
	end
end

post '/export_data' do
	if display.found
		begin
			anfrage = (params[:query])
			data_table = display.found.teilgraph_ausgeben(anfrage, :string)
			''
		rescue StandardError => e
			e.message
		end
	end
end

get '/export/data_table.csv' do
	if data_table
		headers "Content-Type" => "data:Application/octet-stream; charset=utf8"
		data_table
	end
end

get '/doc/:filename' do
	headers "Content-Type" => "data:Application/octet-stream; charset=utf8"
	send_file 'doc/' + params[:filename]
end