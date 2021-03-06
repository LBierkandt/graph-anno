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

require 'sinatra.rb'
require 'haml.rb'
require 'fileutils.rb'
require 'json.rb'
require 'yaml.rb'
require 'rexml/document.rb'

require './lib/extensions.rb'
require './lib/model.rb'
require './lib/controller.rb'

controller = GraphController.new

configure do
  class << settings
    def server_settings
      { :timeout => 300 }
    end
  end
end

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
