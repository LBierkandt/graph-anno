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

require 'sinatra.rb'
require 'haml.rb'
require 'fileutils.rb'
require 'rexml/document.rb'

require './lib/extensions.rb'
require './lib/node_or_edge.rb'
require './lib/node.rb'
require './lib/edge.rb'
require './lib/graph.rb'
require './lib/annotator.rb'
require './lib/attributes.rb'
require './lib/graph_conf.rb'
require './lib/tagset.rb'
require './lib/toolbox_module.rb'
require './lib/paula_exporter.rb'
require './lib/salt_exporter.rb'
require './lib/graph_controller.rb'

controller = GraphController.new

set :root, Dir.pwd
set :static_cache_control, [:'no-cache']

before do
	controller.sinatra = self
	params[:sentence] = params[:sentence].split(',') if params[:sentence].is_a?(String)
	request.cookies['traw_sentence'] = request.cookies['traw_sentence'].split('&') if request.cookies['traw_sentence']
end

get '/' do
	controller.root
end

get '/:method/?:param?' do |method, param|
	if controller.respond_to?(method)
		if param
			controller.send(method, param)
		else
			controller.send(method)
		end
	end
end

post '/:method/?:param?' do |method, param|
	if controller.respond_to?(method)
		if param
			controller.send(method, param)
		else
			controller.send(method)
		end
	end
end
