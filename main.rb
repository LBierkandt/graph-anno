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
require 'fileutils'

require './lib/anno_graph'
require './lib/toolbox_module'
require './lib/paula_exporter'
require './lib/salt_exporter'
require './lib/expansion_module'
require './lib/graph_controller'

controller = GraphController.new

set :root, Dir.pwd

before do
	controller.sinatra = self
end

get '/' do
	controller.root
end

get '/:method/?:param?' do |method, param|
	if param
		controller.send(method, param)
	else
		controller.send(method)
	end
end

post '/:method/?:param?' do |method, param|
	if param
		controller.send(method, param)
	else
		controller.send(method)
	end
end
