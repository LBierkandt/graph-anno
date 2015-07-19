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

require 'sinatra.rb'
require 'haml.rb'
require 'fileutils.rb'
require 'rexml/document.rb'

require './lib/anno_graph.rb'
require './lib/toolbox_module.rb'
require './lib/paula_exporter.rb'
require './lib/salt_exporter.rb'
require './lib/graph_controller.rb'

controller = GraphController.new

set :root, Dir.pwd

before do
	controller.sinatra = self
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
