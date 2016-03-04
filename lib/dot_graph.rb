class DotGraph
	def initialize(name, options = {})
		@name = name
		@options = options
		@nodes = []
		@edges = []
		@subgraphs = []
	end

	def add_nodes(id, options = {})
		@nodes << {:id => id, :options => options}
	end

	def add_edges(start_id, end_id, options = {})
		@edges << {:start => start_id, :end => end_id, :options => options}
	end

	def subgraph(options = {})
		g = DotGraph.new(('a'..'z').to_a.shuffle[0..7].join, options)
		@subgraphs << g
		return g
	end

	def to_s(type = 'digraph')
		s = "#{type} #{@name}{"
		s << options_string(@options, ';')
		@nodes.each do |n|
			s << "#{n[:id]}[#{options_string(n[:options])}]"
		end
		@edges.each do |e|
			s << "#{e[:start]}->#{e[:end]}[#{options_string(e[:options])}]"
		end
		@subgraphs.each do |sg|
			s << sg.to_s('subgraph')
		end
		s << '}'
		return s
	end

	private

	def options_string(h, sep = ',')
		s = ''
		h.each do |k, v|
			s << "#{k}=\"#{v}\"#{sep}"
		end
		return s
	end
end
