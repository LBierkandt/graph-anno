class Log
	attr_reader :steps, :graph, :current_index
	attr_accessor :user

	def initialize(graph, user = '')
		@graph = graph
		@steps = []
		@current_index = -1
		@user = user
	end

	# @return [Hash] a hash representing the log
	def to_h
		{
			'steps' => @steps.map{|step| step.to_h},
			'current_index' => @current_index,
		}
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
	attr_reader :user, :time, :command, :changes, :log

	def initialize(h)
		@log = h[:log]
		@user = h[:user] || @log.user
    @command = h[:command]
		@time = Time.now.utc
    @changes = []
	end

	# @return [Hash] a hash representing the step
	def to_h
		{
			'user' => @user,
			'time' => @time.to_s,
			'command' => @command,
			'changes' => @changes.map{|change| change.to_h},
		}
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
		@action = h[:action]
		@element_type = h[:element].is_a?(Node) ? :node : :edge
		@element_id = h[:element].id
		@data = case h[:action]
		when :create, :delete
			h[:element].to_h
		when :update
			{
				:before => h[:element].attr.to_h,
				:after  => h[:element].attr.clone.merge!(h[:attr]).remove_empty!.to_h
			}
		end
	end

	# @return [Hash] a hash representing the change
	def to_h
		{
			'action' => @action,
			'element' => "#{@element_type}_#{@element_id}",
			'data' => @data,
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
		element.attr = Attributes.new({:graph => @step.log.graph, :raw => true}.merge(@data[before_or_after]))
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
