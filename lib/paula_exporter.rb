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

class AnnoGraph

	def export_paula(corpus_name, doc_name = nil)
		# einzuführender Parameter: syntaktische Kanten als dominierend ansehen?

		if !doc_name then doc_name = 'doc1' end
		corpus_name.gsub!(/\s/, '_')
		doc_name.gsub!(/\s/, '_')
		puts "generating PAULA corpus document \"#{corpus_name}/#{doc_name}\""

		corpus_path = 'exports/paula/' + corpus_name
		doc_path = corpus_path + "/#{doc_name}/"
		FileUtils.mkdir_p(doc_path)

		# DTDs kopieren
		FileUtils.cp_r('conf/PAULA_DTDs/.', doc_path)

		# XML-Dokumente mit grundlegender Struktur anlegen
		dtd = {
			'text'=>'text',
			'tok'=>'mark',
			'sentence_seg'=>'mark',
			'tok_multiFeat'=>'multiFeat',
			'sentence_seg_multiFeat'=>'multiFeat',
			'synNode'=>'struct',
			'synNode_multiFeat'=>'multiFeat',
			'domrel_multiFeat'=>'multiFeat',
			'semNode'=>'struct',
			'semNode_multiFeat'=>'multiFeat',
			'nondomrel'=>'rel',
			'nondomrel_multiFeat'=>'multiFeat',
			'anno'=>'struct'
		}
		docs = {}
		paula = {}
		dtd.keys.each do |dt|
			docs[dt] = REXML::Document.new
			docs[dt] << REXML::DocType.new('paula', "SYSTEM 'paula_"+dtd[dt]+".dtd'")
			docs[dt] << REXML::XMLDecl.new('1.0', 'UTF-8', 'no')
			paula[dt] = docs[dt].add_element('paula', {'version' => '1.1'})
			case dt
				when 'text'
					paula[dt].add_element('header', {'paula_id' => "#{corpus_name}.#{doc_name}.#{dt}", 'type' => 'text'})
				else
					paula[dt].add_element('header', {'paula_id' => "#{corpus_name}.#{doc_name}.#{dt}"})
			end
		end

		# Elementlisten für die einzelnen XML-Dokumente anlegen
		text_body = paula['text'].add_element('body')
		tok_list = paula['tok'].add_element('markList', {'xmlns:xlink'=>'http://www.w3.org/1999/xlink', 'type'=>'tok', 'xml:base'=>"#{corpus_name}.#{doc_name}.text.xml"})
		sentence_list = paula['sentence_seg'].add_element('markList', {'xmlns:xlink'=>'http://www.w3.org/1999/xlink', 'type'=>'sentence', 'xml:base'=>"#{corpus_name}.#{doc_name}.tok.xml"})
		tok_feat_list = paula['tok_multiFeat'].add_element('multiFeatList', {'xmlns:xlink'=>'http://www.w3.org/1999/xlink', 'type'=>'multiFeat', 'xml:base'=>"#{corpus_name}.#{doc_name}.tok.xml"})
		sentence_feat_list = paula['sentence_seg_multiFeat'].add_element('multiFeatList', {'xmlns:xlink'=>'http://www.w3.org/1999/xlink', 'type'=>'multiFeat', 'xml:base'=>"#{corpus_name}.#{doc_name}.sentence_seg.xml"})
		synstruct_list = paula['synNode'].add_element('structList', {'xmlns:xlink'=>'http://www.w3.org/1999/xlink', 'type'=>'synNode'})
		synstruct_feat_list = paula['synNode_multiFeat'].add_element('multiFeatList', {'xmlns:xlink'=>'http://www.w3.org/1999/xlink', 'type'=>'multiFeat', 'xml:base'=>"#{corpus_name}.#{doc_name}.synNode.xml"})
		domrel_feat_list = paula['domrel_multiFeat'].add_element('multiFeatList', {'xmlns:xlink'=>'http://www.w3.org/1999/xlink', 'type'=>'multiFeat', 'xml:base'=>"#{corpus_name}.#{doc_name}.synNode.xml"})
		semstruct_list = paula['semNode'].add_element('structList', {'xmlns:xlink'=>'http://www.w3.org/1999/xlink', 'type'=>'semNode'})
		semstruct_feat_list = paula['semNode_multiFeat'].add_element('multiFeatList', {'xmlns:xlink'=>'http://www.w3.org/1999/xlink', 'type'=>'multiFeat', 'xml:base'=>"#{corpus_name}.#{doc_name}.semNode.xml"})
		rel_list = paula['nondomrel'].add_element('relList', {'xmlns:xlink'=>'http://www.w3.org/1999/xlink', 'type'=>'nondomrel'})
		rel_feat_list = paula['nondomrel_multiFeat'].add_element('multiFeatList', {'xmlns:xlink'=>'http://www.w3.org/1999/xlink', 'type'=>'multiFeat', 'xml:base'=>"#{corpus_name}.#{doc_name}.nondomrel.xml"})
		anno_list = paula['anno'].add_element('structList', {'xmlns:xlink'=>'http://www.w3.org/1999/xlink', 'type'=>'annoSet'})

		text = ''
		tok_no = 0
		sentence_no = 0
		rel_no = 0
		elem_ids = {}
		self.sentence_nodes.each do |sentence| # satzweise vorgehen
			ns_nodes = sentence.nodes
			ns_tokens = sentence.sentence_tokens
			sentence_no += 1
			# Tokens anlegen
			ns_tokens.each do |tok|
				tok_no += 1
				elem_ids[tok] = 'tok_' + tok_no.to_s
				tok_list.add_element('mark', {'id'=>elem_ids[tok], 'xlink:href'=>"#xpointer(string-range(//body,'',#{(text.length+1).to_s},#{tok.token.length.to_s}))"})
				mf = tok_feat_list.add_element('multiFeat', {'xlink:href'=>'#'+elem_ids[tok]})
				tok.attr.each do |k,v|
					case k
						when 'token'
						else
							mf.add_element('feat', {'name' => k, 'value' => v})
					end
				end
				text << tok.token + ' '
			end
			# Satz anlegen
			if ns_tokens != [] # nur Satz anlegen, wenn es auch mindestens ein Token gibt
				sentence_list.add_element('mark', {'id'=>'sentence_'+sentence_no.to_s, 'xlink:href'=>"#xpointer(id('#{elem_ids[ns_tokens.first]}')/range-to(id('#{elem_ids[ns_tokens.last]}')))"})
				mf = sentence_feat_list.add_element('multiFeat', {'xlink:href'=>'#sentence_'+sentence_no.to_s})
				sentence.attr.each do |k,v|
					mf.add_element('feat', {'name' => k, 'value' => v})
				end
			end
		end
		# Syn-Knoten anlegen
		structs = {}
		synnodes = @nodes.values.select{|k| k['s-layer'] == 't' && !k.token}
		synnodes.each_with_index do |node,i|
			elem_ids[node] = 'synNode_' + (i+1).to_s
			structs[node] = synstruct_list.add_element('struct', {'id'=>elem_ids[node]})
			mf = synstruct_feat_list.add_element('multiFeat', {'xlink:href'=>'#'+elem_ids[node]})
			node.attr.each do |k,v|
				case k
					when 's-layer', 'f-layer'
					else
						mf.add_element('feat', {'name' => k, 'value' => v})
				end
			end
		end
		# ausgehende (dominierende) Kanten hinzufügen
		synnodes.each do |node|
			node.out.select{|k| k['s-layer'] == 't'}.each do |edge|
				rel_no += 1
				if edge.end.token
					target = "#{corpus_name}.#{doc_name}.tok.xml##{elem_ids[edge.end]}"
				else
					target = '#' + elem_ids[edge.end]
				end
				structs[edge.start].add_element('rel', {'id'=>'rel_'+rel_no.to_s, 'type'=>'edge', 'xlink:href'=>target})
				mf = domrel_feat_list.add_element('multiFeat', {'xlink:href'=>'#rel_'+rel_no.to_s})
				edge.attr.each do |k,v|
					case k
						when 's-layer', 'f-layer'
						else
							mf.add_element('feat', {'name' => k, 'value' => v})
					end
				end
			end
		end
		# Sem-Knoten anlegen
		@nodes.values.select{|k| k['s-layer'] != 't' && !k.token && k.type != 's'}.each_with_index do |node,i|
			elem_ids[node] = 'semNode_' + (i+1).to_s
			semstruct_list.add_element('struct', {'id'=>elem_ids[node]})
			mf = semstruct_feat_list.add_element('multiFeat', {'xlink:href'=>'#'+elem_ids[node]})
			node.attr.each do |k,v|
				case k
					when 's-layer', 'f-layer'
					else
						mf.add_element('feat', {'name' => k, 'value' => v})
				end
			end
		end
		# nicht-dominierende Kanten anlegen
		@edges.values.select{|k| k.type == 'a' && !(k['s-layer'] == 't' && k.start['s-layer'] == 't')}.each_with_index do |edge,i|
			rel_id = 'rel_' + (i+1).to_s
			if edge.start.token
				source = "#{corpus_name}.#{doc_name}.tok.xml##{elem_ids[edge.start]}"
			elsif edge.start['s-layer'] == 't'
				source = "#{corpus_name}.#{doc_name}.synNode.xml##{elem_ids[edge.start]}"
			else
				source = "#{corpus_name}.#{doc_name}.semNode.xml##{elem_ids[edge.start]}"
			end
			if edge.end.token
				target = "#{corpus_name}.#{doc_name}.tok.xml##{elem_ids[edge.end]}"
			elsif edge.end['s-layer'] == 't'
				target = "#{corpus_name}.#{doc_name}.synNode.xml##{elem_ids[edge.end]}"
			else
				target = "#{corpus_name}.#{doc_name}.semNode.xml##{elem_ids[edge.end]}"
			end
			rel_list.add_element('rel', {'id'=>rel_id, 'xlink:href'=>source, 'target'=>target})
			mf = rel_feat_list.add_element('multiFeat', {'xlink:href'=>'#'+rel_id})
			edge.attr.each do |k,v|
				case k
					when 's-layer', 'f-layer'
					else
						mf.add_element('feat', {'name' => k, 'value' => v})
				end
			end
		end
		text_body.text = text.strip

		# AnnoSet anlegen
		s = anno_list.add_element('struct', {'id'=>'anno_1'})
			s.add_element('rel', {'id'=>'rel_1', 'xlink:href'=>"#{corpus_name}.#{doc_name}.text.xml"})
			s.add_element('rel', {'id'=>'rel_2', 'xlink:href'=>"#{corpus_name}.#{doc_name}.tok.xml"})
		s = anno_list.add_element('struct', {'id'=>'anno_2'})
			s.add_element('rel', {'id'=>'rel_3', 'xlink:href'=>"#{corpus_name}.#{doc_name}.sentence_seg.xml"})
			s.add_element('rel', {'id'=>'rel_4', 'xlink:href'=>"#{corpus_name}.#{doc_name}.sentence_seg_multiFeat.xml"})
		s = anno_list.add_element('struct', {'id'=>'anno_3'})
		if synstruct_list.length > 0
			s.add_element('rel', {'id'=>'rel_5', 'xlink:href'=>"#{corpus_name}.#{doc_name}.synNode.xml"})
			s.add_element('rel', {'id'=>'rel_6', 'xlink:href'=>"#{corpus_name}.#{doc_name}.synNode_multiFeat.xml"})
			s.add_element('rel', {'id'=>'rel_7', 'xlink:href'=>"#{corpus_name}.#{doc_name}.domrel_multiFeat.xml"})
		end
		s = anno_list.add_element('struct', {'id'=>'anno_4'})
		if semstruct_list.length > 0
			s.add_element('rel', {'id'=>'rel_8', 'xlink:href'=>"#{corpus_name}.#{doc_name}.semNode.xml"})
			s.add_element('rel', {'id'=>'rel_9', 'xlink:href'=>"#{corpus_name}.#{doc_name}.semNode_multiFeat.xml"})
		end
		if rel_list.length > 0
			s.add_element('rel', {'id'=>'rel_8', 'xlink:href'=>"#{corpus_name}.#{doc_name}.nondomrel.xml"})
			s.add_element('rel', {'id'=>'rel_8', 'xlink:href'=>"#{corpus_name}.#{doc_name}.nondomrel_multiFeat.xml"})
		end

		# Kleiner Hack für XML-Attribute in doppelten Anführungsstrichen
		REXML::Attribute.class_exec do
			def to_string
				%Q[#@expanded_name="#{to_s().gsub(/"/, '&quot;').gsub('&apos;', "'")}"]
			end
		end
		# ... für Text ohne XML-Entities
		REXML::Text.class_exec do
			alias_method :to_s, :value
		end
		# ... und für Text, bei dem keine Leerzeichen verschwinden
		REXML::Formatters::Pretty.class_exec do
			def write_text(node, output)
				s = node.to_s()
				#s.gsub!(/\s/,' ')
				#s.squeeze!(" ")
				s = wrap(s, @width - @level)
				s = indent_text(s, @level, " ", true)
				output << (' '*@level + s)
			end
		end

		# Dateien schreiben
		formatter = REXML::Formatters::Pretty.new
		formatter.compact = true
		formatter.width = 99999999999
		dtd.keys.each do |dt|
			if ['synNode', 'synNode_multiFeat', 'domrel_multiFeat'].include?(dt) and synstruct_list.length == 0
				next
			elsif ['semNode', 'semNode_multiFeat'].include?(dt) and semstruct_list.length == 0
				next
			elsif ['nondomrel', 'nondomrel_multiFeat'].include?(dt) and rel_list.length == 0
				next
			end
			File.open("#{doc_path}#{corpus_name}.#{doc_name}.#{dt}.xml", 'w') do |f|
				formatter.write(docs[dt], f)
			end
		end

	end
end
