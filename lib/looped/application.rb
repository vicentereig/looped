# typed: strict
# frozen_string_literal: true

require 'async'
require 'async/io'
require 'readline'

module Looped
  class Application
    extend T::Sig

    sig { returns(Agent) }
    attr_reader :agent

    sig { returns(Optimizer) }
    attr_reader :optimizer

    sig { returns(State) }
    attr_reader :state

    sig do
      params(
        model: T.nilable(String),
        judge_model: T.nilable(String),
        reflection_model: T.nilable(String),
        max_iterations: Integer,
        optimizer_batch_size: Integer,
        optimizer_interval: Integer
      ).void
    end
    def initialize(
      model: nil,
      judge_model: nil,
      reflection_model: nil,
      max_iterations: 10,
      optimizer_batch_size: 5,
      optimizer_interval: 60
    )
      @state = T.let(State.new, State)
      @agent = T.let(
        Agent.new(
          model: model,
          max_iterations: max_iterations,
          judge_model: judge_model
        ),
        Agent
      )
      @optimizer = T.let(
        Optimizer.new(
          state: @state,
          batch_size: optimizer_batch_size,
          check_interval: optimizer_interval,
          reflection_model: reflection_model
        ),
        Optimizer
      )
      @running = T.let(false, T::Boolean)
    end

    sig { void }
    def run
      @running = true

      puts banner
      puts "Type a coding task and press Enter. Type 'quit' to exit."
      puts "Type 'status' to see optimization status."
      puts ""

      Async do |task|
        # Start the optimizer in the background
        optimizer_task = task.async do
          @optimizer.start
        end

        # Run the interactive loop
        begin
          interactive_loop
        ensure
          @optimizer.stop
          optimizer_task.stop
        end
      end
    end

    sig { params(task: String, context: String).returns(Types::TrainingResult) }
    def run_task(task:, context: '')
      @agent.run(task: task, context: context)
    end

    sig { void }
    def stop
      @running = false
      @optimizer.stop
    end

    private

    sig { void }
    def interactive_loop
      while @running
        input = Readline.readline('looped> ', true)

        if input.nil? || input.strip.downcase == 'quit'
          puts "\nGoodbye!"
          @running = false
          break
        end

        next if input.strip.empty?

        handle_input(input.strip)
      end
    end

    sig { params(input: String).void }
    def handle_input(input)
      case input.downcase
      when 'status'
        show_status
      when 'history'
        show_history
      when 'help'
        show_help
      when /^context\s+(.+)/i
        set_context(T.must($1))
      else
        execute_task(input)
      end
    end

    sig { void }
    def show_status
      instructions = @state.load_instructions
      buffer = @state.peek_training_buffer

      puts ""
      puts "=== Looped Status ==="
      puts ""

      if instructions
        puts "Current Instructions:"
        puts "  Generation: #{instructions.generation}"
        puts "  Best Score: #{instructions.score.round(2)}/10"
        puts "  Updated: #{instructions.updated_at}"
      else
        puts "No optimized instructions yet (using defaults)"
      end

      puts ""
      puts "Training Buffer: #{buffer.length} results"
      puts "Optimizer: #{@optimizer.running ? 'Running' : 'Stopped'}"
      puts ""
    end

    sig { void }
    def show_history
      buffer = @state.peek_training_buffer

      if buffer.empty?
        puts "\nNo tasks completed yet.\n"
        return
      end

      puts ""
      puts "=== Recent Tasks ==="
      puts ""

      buffer.last(5).each_with_index do |result, i|
        puts "#{i + 1}. #{result.task.truncate(60)}"
        puts "   Score: #{result.score.round(2)}/10 | #{result.timestamp}"
        puts ""
      end
    end

    sig { void }
    def show_help
      puts <<~HELP

        === Looped Commands ===

        <task>     Execute a coding task
        status     Show optimization status
        history    Show recent task history
        help       Show this help message
        quit       Exit the application

        === Environment Variables ===

        LOOPED_MODEL           Agent model (default: gpt-4o-mini)
        LOOPED_JUDGE_MODEL     Judge model (default: gpt-4o-mini)
        LOOPED_REFLECTION_MODEL  GEPA reflection model (default: gpt-4o-mini)

      HELP
    end

    sig { params(context: String).void }
    def set_context(context)
      @current_context = context
      puts "\nContext set to: #{context}\n"
    end

    sig { params(task: String).void }
    def execute_task(task)
      puts "\nExecuting task..."
      puts ""

      context = @current_context || ''

      begin
        result = @agent.run(task: task, context: context)

        puts "=== Result ==="
        puts ""
        puts "Score: #{result.score.round(2)}/10"
        puts ""
        puts "Solution:"
        puts result.solution
        puts ""
        puts "Feedback:"
        puts result.feedback
        puts ""
      rescue StandardError => e
        puts "Error: #{e.message}"
        puts e.backtrace&.first(5)&.join("\n")
        puts ""
      end
    end

    sig { returns(String) }
    def banner
      <<~BANNER

        ╦  ┌─┐┌─┐┌─┐┌─┐┌┬┐
        ║  │ ││ │├─┘├┤  ││
        ╩═╝└─┘└─┘┴  └─┘─┴┘

        Self-improving coding agent powered by DSPy.rb + GEPA

      BANNER
    end
  end
end

# Add String#truncate for display
unless String.method_defined?(:truncate)
  class String
    def truncate(length, omission: '...')
      return self if self.length <= length

      "#{self[0, length - omission.length]}#{omission}"
    end
  end
end
