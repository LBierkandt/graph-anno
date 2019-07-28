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

# dependent classes
require_relative './model/node_or_edge.rb'
require_relative './model/node.rb'
require_relative './model/edge.rb'
require_relative './model/annotator.rb'
require_relative './model/attributes.rb'
require_relative './model/graph_conf.rb'
require_relative './model/anno_layer.rb'
require_relative './model/tagset.rb'
require_relative './model/nlp.rb'
require_relative './model/automat.rb'
# graph modules
require_relative './model/toolbox_importer.rb'
require_relative './model/paula_exporter.rb'
require_relative './model/salt_exporter.rb'
require_relative './model/graph_persistence_module.rb'
require_relative './model/parser_module.rb'
require_relative './model/graph_search_module.rb'
# graph class
require_relative './model/graph.rb'
