class DotGraph
	DotNode = Struct.new(:id, :options)
	DotEdge = Struct.new(:start, :end, :options)

	def initialize(name, options = {})
		@name = name
		@options = options
		@nodes = []
		@edges = []
		@subgraphs = []
	end

	def add_nodes(source, options = {})
		@nodes << DotNode.new(get_id(source), options)
		@nodes.last
	end

	def add_edges(start, target, options = {})
		@edges << DotEdge.new(get_id(start), get_id(target), options)
		@edges.last
	end

	def subgraph(options = {})
		@subgraphs << DotGraph.new(('a'..'z').to_a.shuffle[0..15].join, options)
		@subgraphs.last
	end

	def to_s(type = 'digraph')
		return '' if type == 'subgraph' && (@nodes + @edges).empty?
		"#{type} #{@name}{" +
			options_string(@options, ';') +
			@nodes.map{|n| "#{n.id}[#{options_string(n.options)}]"}.join +
			@edges.map{|e| "#{e.start}->#{e.end}[#{options_string(e.options)}]"}.join +
			@subgraphs.map{|sg| sg.to_s('subgraph')}.join +
			'}'
	end

	private

	def options_string(h, sep = ',')
		h.map{|k, v| "#{k}=\"#{v}\"#{sep}"}.join
	end

	def get_id(source)
		source.respond_to?(:id) ? source.id.to_s : source.to_s
	end
end
