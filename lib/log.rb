require 'time'

class Log
	attr_reader :steps, :graph, :current_index
	attr_accessor :user

	def initialize(graph, user = nil)
		@graph = graph
		@steps = []
		@current_index = -1
		@user = user
	end

	# @return [Hash] a hash representing the log
	def to_h
		{
			:steps => @steps.map{|step| step.to_h},
			:current_index => @current_index,
		}
	end

	# provides the to_json method needed by the JSON gem
	def to_json(*a)
		self.to_h.to_json(*a)
	end

	# serializes self in a JSON file
	# @param path [String] path to the JSON file
	def write_json_file(path)
		puts 'Writing log file "' + path + '"...'
		file = open(path, 'w')
		file.write(JSON.pretty_generate(self, :indent => ' ', :space => '').encode('UTF-8'))
		file.close
		puts 'Wrote "' + path + '".'
	end

	# reads a JSON log file into self
	# @param path [String] path to the JSON file
	def read_json_file(path)
		puts 'Reading log file "' + path + '" ...'
		file = open(path, 'r:utf-8')
		data = JSON.parse(file.read)
		file.close

		@steps = data['steps'].map{|s| Step.new_from_hash(s.merge(:log => self))}
		@current_index = data['current_index']
	end

	# @return [Step] the current step
	def current_step
		if @current_index >= 0
			@steps[@current_index]
		else
			nil
		end
	end

	# @param h [Hash] a hash containing the keys :user and :command
	# @return [Step] the created step
	def add_step(h)
		# deletes all following steps if current step is not the last one
		@steps = @steps.slice(0, @current_index + 1)
		@steps << Step.new(h.merge(:log => self))
		@current_index += 1
		return current_step
	end

	# @param steps [Int] the number of steps to be undone
	def undo(steps = 1)
		steps.times do
			break unless current_step
			current_step.undo
			@current_index -= 1
		end
	end

	# @param steps [Int] the number of steps to be redone
	def redo(steps = 1)
		steps.times do
			break if current_step == @steps.last
			@current_index += 1
			current_step.redo
		end
	end

	# @param i [Int] the index of the step which is to be restored
	def go_to_step(i)
		self.undo while i < @current_index
		self.redo while i > @current_index
	end

	# @return [Int] the maximum step index
	def max_index
		@steps.length - 1
	end
end

class Step
	attr_reader :user, :time, :command, :log
	attr_accessor :changes

	def initialize(h)
		@log = h[:log]
		@user = h[:user] || @log.user
		@user = @log.graph.get_annotator(:id => @user) if @user.is_a?(Integer)
    @command = h[:command]
		@time = h[:time] ? Time.parse(h[:time]) : Time.now.utc
    @changes = []
	end

	# @return [Hash] a hash representing the step
	def to_h
		{
			:user => @user ? @user.id : nil,
			:time => @time.to_s,
			:command => @command,
			:changes => @changes.map{|change| change.to_h},
		}
	end

	def self.new_from_hash(h)
		step = Step.new(h.symbolize_keys)
		step.changes = h['changes'].map{|c| Change.new(c.symbolize_keys.merge(:step => step))}
		return step
	end

	# @param h [Hash] a hash containing the keys :action, :element and, in case of ":action => :update", :attr
	def add_change(h)
		@changes << Change.new(h.merge(:step => self)) if h[:element]
	end

	def undo
		@changes.reverse.each do |change|
			change.undo
		end
	end

	def redo
		@changes.each do |change|
			change.redo
		end
	end

	def done?
		@log.steps.index(self) <= @log.current_index
	end
end

class Change
	attr_reader :action, :element, :data, :step

	def initialize(h)
		@step = h[:step]
		@action = h[:action].to_sym
		if h[:element_type] && h[:element_id]
			@element_type = h[:element_type].to_sym
			@element_id = h[:element_id]
		else
			@element_type = h[:element].is_a?(Node) ? :node : :edge
			@element_id = h[:element].id
		end
		@data = case @action
		when :create, :delete
			h[:data] ? h[:data].symbolize_keys : h[:element].to_h
		when :update
			if h[:data]
				{
					:before => h[:data]['before'].symbolize_keys,
					:after => h[:data]['after'].symbolize_keys
				}
			else
				{
					:before => h[:element].attr.to_h,
					:after  => h[:element].attr.clone.annotate_with(h[:attr]).remove_empty!.to_h
				}
			end
		end
	end

	# @return [Hash] a hash representing the change
	def to_h
		{
			:action => @action,
			:element_type => @element_type,
			:element_id => @element_id,
			:data => @data,
		}
	end

	def undo
		case @action
		when :create
			delete
		when :delete
			create
		when :update
			update(:before)
		end
	end

	def redo
		send(@action)
	end

	private

	def create
		case @element_type
		when :node
			@step.log.graph.add_node(@data.merge(:raw => true))
		when :edge
			@step.log.graph.add_edge(@data.merge(:raw => true))
		end
	end

	def delete
		element.delete
	end

	def update(before_or_after = :after)
		element.attr = Attributes.new({:host => element, :raw => true}.merge(@data[before_or_after]))
	end

	def element
		case @element_type
		when :node
			@step.log.graph.nodes[@element_id]
		when :edge
			@step.log.graph.edges[@element_id]
		end
	end
end
