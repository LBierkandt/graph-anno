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

class AnnoGraph

	def export_saltxml(textname)
		require 'fileutils'
		pfad = 'exports/' + textname
		FileUtils.mkdir_p(pfad + '/corpus')
		
		@nodes.values.each{|k| k.salt_init}
		
		graphpfad = 'salt:/corpus/corpus_document/corpus_document_graph'
		
		# Präambel
		saltxml = %q{<?xml version="1.0" encoding="UTF-8"?>
<sDocumentStructure:SDocumentGraph xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:graph="graph" xmlns:sDocumentStructure="sDocumentStructure" xmlns:saltCore="saltCore">
<labels xsi:type="graph:Identifier" sentence="graph" name="id" valueString="}+graphpfad+%q{"/>
}

		# Text/Korpusstring
		tokens = @nodes.values.select{|k| k.token}.sort do |a,b|
			if a.sentence != b.sentence
				a.sentence <=> b.sentence
			else
				a.tokenid <=> b.tokenid
			end
		end
		korpusstring = ''
		tokens.each do |tok|
			tok.salt_attr['start'] = korpusstring.length.to_s
			korpusstring += tok.token
			tok.salt_attr['end'] = korpusstring.length.to_s
			korpusstring += ' '
		end
		korpusstring.strip!
		
		# Korpusstring als erster Knoten
		saltxml += %q{  <nodes xsi:type="sDocumentStructure:STextualDS">
    <labels xsi:type="saltCore:SFeature" sentence="salt" name="SNAME" valueString="sText1"/>
    <labels xsi:type="saltCore:SFeature" sentence="saltCommon" name="SDATA" valueString="}+korpusstring+%q{">
      <labels name="SVAL_TYPE" valueString="STEXT"/>
    </labels>
    <labels xsi:type="saltCore:SElementId" sentence="graph" name="id" valueString="}+graphpfad+%q{#sText1"/>
  </nodes>
}
		
		knotenzaehler = 1
		
		# Tokens
		tokens.each_with_index do |tok, index|
			saltxml += saltXML_knoten_schreiben(tok, :token, index, graphpfad)
			tok.salt_attr['index'] = knotenzaehler.to_s
			knotenzaehler += 1
		end
		
		# andere Knoten
		@nodes.values.select{|k| !k.token}.each_with_index do |knot, index|
			saltxml += saltXML_knoten_schreiben(knot, :knoten, index, graphpfad)
			knot.salt_attr['index'] = knotenzaehler.to_s
			knotenzaehler += 1
		end
		
		# Satzspannen
		saetzegraph = AnnoGraph.new
		self.sentences.each_with_index do |ns, index|
			knot = saetzegraph.add_node(:attr => {'sentenceID' => ns})
			knot.salt_init
			saltxml += saltXML_knoten_schreiben(knot, :satz, index, graphpfad)
			knot.salt_attr['index'] = knotenzaehler.to_s
			knotenzaehler += 1
		end
		
		
		# Tokenverankerung
		tokens.each do |tok|
			name = 'sTextRel' + tok.salt_attr['nummer']
			saltxml += %q{  <edges xsi:type="sDocumentStructure:STextualRelation" source="//@nodes.}+tok.salt_attr['index']+%q{" target="//@nodes.0">
    <labels xsi:type="saltCore:SFeature" sentence="salt" name="SNAME" valueString="}+name+%q{"/>
    <labels xsi:type="saltCore:SFeature" sentence="saltCommon" name="SSTART" valueString="}+tok.salt_attr['start']+%q{">
      <labels name="SVAL_TYPE" valueString="SNUMERIC"/>
    </labels>
    <labels xsi:type="saltCore:SFeature" sentence="saltCommon" name="SEND" valueString="}+tok.salt_attr['end']+%q{">
      <labels name="SVAL_TYPE" valueString="SNUMERIC"/>
    </labels>
    <labels xsi:type="saltCore:SElementId" sentence="graph" name="id" valueString="}+graphpfad+'#'+name+%q{"/>
  </edges>
}
		end
		
		# Satzspannen verbinden
		satzrelzaehler = 1
		saetzegraph.nodes.values.each do |satz|
			tokens = @nodes.values.select{|k| k.token and k.sentence == satz['sentenceID']}
			tokens.each do |tok|
				name = 'spanningRel' + satzrelzaehler.to_s
				saltxml += '  <edges xsi:type="sDocumentStructure:SSpanningRelation" source="//@nodes.'+satz.salt_attr['index']+'" target="//@nodes.'+tok.salt_attr['index']+'">'+"\n"
				# Labels
				saltxml += '    <labels xsi:type="saltCore:SFeature" sentence="salt" name="SNAME" valueString="'+name+'"/>'+"\n"
				saltxml += '    <labels xsi:type="saltCore:SElementId" sentence="graph" name="id" valueString="'+graphpfad+'#'+name+'"/>'+"\n"
				# Kanten-Schluß-Täg
				saltxml += '  </edges>'+"\n"
				satzrelzaehler += 1
			end
		end
		
		# andere Kanten
		@edges.values.select{|k| k.type == 'a'}.each_with_index do |kante, index|
			if kante['s-layer'] == 't'
				kantentyp = 'SDominanceRelation'
			else
				kantentyp = 'SPointingRelation'
			end
			# start und end als Position in der Knoten-Liste
			name = 'edge' + (index+1).to_s
			saltxml += '  <edges xsi:type="sDocumentStructure:'+kantentyp+'" source="//@nodes.'+kante.start.salt_attr['index']+'" target="//@nodes.'+kante.end.salt_attr['index']+'">'+"\n"
			# Labels
			saltxml += '    <labels xsi:type="saltCore:SFeature" sentence="salt" name="SNAME" valueString="'+name+'"/>'+"\n"
			saltxml += '    <labels xsi:type="saltCore:SElementId" sentence="graph" name="id" valueString="'+graphpfad+'#'+name+'"/>'+"\n"
			# Attribute
			attribute = kante.attr.reject do |s,w|
				[
					'f-layer',
					's-layer'
				].include?(s)
			end
			attribute.each do |schluessel, wert|
				saltxml += '    <labels xsi:type="saltCore:SAnnotation" sentence="annotation" name="'+schluessel+'" valueString="'+wert+'">'+"\n"
				saltxml += '      <labels name="SVAL_TYPE" valueString="STEXT"/>'+"\n"
				saltxml += '    </labels>'+"\n"
			end
			# Kanten-Schluß-Täg
			saltxml += '  </edges>'+"\n"
		end
		
		# Datei-Ende
		saltxml += '</sDocumentStructure:SDocumentGraph>'+"\n"
	
	
		# Dateien schreiben
		File.open(pfad + '/corpus/corpus_document.salt', 'w'){|f| f.write(saltxml)}
		File.open(pfad + '/saltProject.salt', 'w') do |f|
			f.write(%q{<?xml version="1.0" encoding="UTF-8"?>
<saltCommon:SaltProject xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:sCorpusStructure="sCorpusStructure" xmlns:saltCommon="saltCommon" xmlns:saltCore="saltCore">
  <sCorpusGraphs>
    <labels xsi:type="saltCore:SElementId" sentence="graph" name="id" valueString="corpusGraph1"/>
    <nodes xsi:type="sCorpusStructure:SCorpus">
      <labels xsi:type="saltCore:SFeature" sentence="salt" name="SNAME" valueString="corpus"/>
      <labels xsi:type="saltCore:SElementId" sentence="graph" name="id" valueString="salt:/corpus"/>
    </nodes>
    <nodes xsi:type="sCorpusStructure:SDocument">
      <labels xsi:type="saltCore:SFeature" sentence="salt" name="SNAME" valueString="corpus_document"/>
      <labels xsi:type="saltCore:SElementId" sentence="graph" name="id" valueString="salt:/corpus/corpus_document"/>
      <labels xsi:type="saltCore:SFeature" sentence="salt" name="SDOCUMENT_GRAPH_LOCATION" valueString="file:./corpus/corpus_document.salt"/>
    </nodes>
    <edges xsi:type="sCorpusStructure:SCorpusDocumentRelation" source="//@sCorpusGraphs.0/@nodes.0" target="//@sCorpusGraphs.0/@nodes.1">
      <labels xsi:type="saltCore:SFeature" sentence="salt" name="SNAME" valueString="corpDocRel1"/>
      <labels xsi:type="saltCore:SElementId" sentence="graph" name="id" valueString="salt:/corpDocRel1"/>
    </edges>
  </sCorpusGraphs>
</saltCommon:SaltProject>}
			)
		end
	
	end
	
	def saltXML_knoten_schreiben(knot, knotentyp, index, graphpfad)
		saltxml = ''
		
		knot.salt_attr['nummer'] = (index+1).to_s
		if knotentyp == :token
			knotentyp = 'SToken'
			knotenname = 'sTok' + knot.salt_attr['nummer']
		elsif knotentyp == :knoten
			knotentyp = 'SStructure'
			knotenname = 'sStruc' + knot.salt_attr['nummer']
		elsif knotentyp == :satz
			knotentyp = 'SSpan'
			knotenname = 'sSpan' + knot.salt_attr['nummer']
		end
		saltxml += '  <nodes xsi:type="sDocumentStructure:'+knotentyp+'">'+"\n"
		# Labels
		saltxml += '    <labels xsi:type="saltCore:SFeature" sentence="salt" name="SNAME" valueString="'+knotenname+'"/>'+"\n"
		saltxml += '    <labels xsi:type="saltCore:SElementId" sentence="graph" name="id" valueString="'+graphpfad+'#'+knotenname+'"/>'+"\n"
		# Attribute
		attribute = knot.attr.reject do |s,w|
			[
				'token',
				'f-layer',
				's-layer',
			].include?(s)
		end
		attribute.each do |schluessel, wert|
			saltxml += '    <labels xsi:type="saltCore:SAnnotation" sentence="annotation" name="'+schluessel+'" valueString="'+wert+'">'+"\n"
			saltxml += '      <labels name="SVAL_TYPE" valueString="STEXT"/>'+"\n"
			saltxml += '    </labels>'+"\n"
		end
		# Knoten-Schluß-Täg
		saltxml += '  </nodes>'+"\n"
		
		return saltxml
	end

end

class AnnoNode
	attr_accessor :salt_attr
	def salt_init
		@salt_attr = {}
	end
end