# typed: strict
# frozen_string_literal: true

require 'async'
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

    sig { returns(ConversationMemory) }
    attr_reader :conversation_memory

    sig { returns(IntentRouter) }
    attr_reader :intent_router

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
      @conversation_memory = T.let(ConversationMemory.new, ConversationMemory)
      @intent_router = T.let(IntentRouter.new(model: model), IntentRouter)
      @running = T.let(false, T::Boolean)
      @current_context = T.let(nil, T.nilable(String))
    end

    sig { void }
    def run
      @running = true

      puts banner
      puts "Type a coding task and press Enter. Type 'quit' to exit."
      puts "Type 'status' to see optimization status, 'conversation' for history."
      if @conversation_memory.turn_count > 0
        puts "Restored #{@conversation_memory.turn_count} conversation turn(s) from previous session."
      end
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
      when 'conversation'
        show_conversation
      when 'clear'
        clear_conversation
      when 'help'
        show_help
      when /^context\s+(.+)/i
        set_context(T.must($1))
      else
        process_with_intent(input)
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

        <task>       Execute a coding task
        <number>     Execute suggestion #N from previous response
        status       Show optimization status
        history      Show recent task history (training buffer)
        conversation Show conversation history
        clear        Clear conversation history
        help         Show this help message
        quit         Exit the application

        === Tips ===

        After getting suggestions, type a number (1, 2, 3) to implement that suggestion.
        You can also say "go for 1", "option 2", "the first one", etc.

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

    sig { params(input: String).void }
    def process_with_intent(input)
      context = @conversation_memory.to_context

      # Classify intent
      classification = @intent_router.classify(input: input, context: context)

      puts ""
      puts "[Intent: #{classification.intent.serialize}] #{classification.reasoning}"
      puts ""

      # Execute the resolved task
      execute_resolved_task(
        original_input: input,
        resolved_task: classification.resolved_task,
        include_previous_context: classification.intent == Types::Intent::FollowUp
      )
    end

    sig { params(original_input: String, resolved_task: String, include_previous_context: T::Boolean).void }
    def execute_resolved_task(original_input:, resolved_task:, include_previous_context: false)
      puts "Executing: #{resolved_task.truncate(80)}"
      puts ""

      context = @current_context || ''

      # For follow-ups, include previous solution context
      if include_previous_context && @conversation_memory.last_turn
        context = "#{context}\n\nPrevious solution:\n#{@conversation_memory.last_turn.solution}"
      end

      begin
        result = @agent.run(task: resolved_task, context: context)

        # Store in conversation memory
        @conversation_memory.add_turn(
          task: original_input,
          resolved_task: resolved_task,
          solution: result.solution,
          score: result.score,
          suggestions: extract_suggestions(result.feedback),
          judgment: @agent.last_judgment
        )

        puts "=== Result ==="
        puts ""
        puts "Score: #{result.score.round(2)}/10"
        puts ""
        puts "Solution:"
        puts result.solution
        puts ""
        puts "Feedback:"
        puts result.feedback

        # Display numbered suggestions
        display_suggestions
      rescue StandardError => e
        puts "Error: #{e.message}"
        puts e.backtrace&.first(5)&.join("\n")
        puts ""
      end
    end

    sig { void }
    def display_suggestions
      suggestions = @conversation_memory.current_suggestions
      return if suggestions.empty?

      puts ""
      puts "Suggestions for improvement:"
      suggestions.each_with_index do |suggestion, i|
        puts "  #{i + 1}. #{suggestion}"
      end
      puts ""
      puts "(Type a number to implement a suggestion)"
      puts ""
    end

    sig { params(feedback: String).returns(T::Array[String]) }
    def extract_suggestions(feedback)
      # If we have a judgment with suggestions, use those
      return @agent.last_judgment.suggestions if @agent.last_judgment&.suggestions&.any?

      # Otherwise try to parse from feedback text
      []
    end

    sig { void }
    def show_conversation
      if @conversation_memory.turn_count == 0
        puts "\nNo conversation history yet.\n"
        return
      end

      puts ""
      puts "=== Conversation History ==="
      puts ""

      @conversation_memory.turns.each do |turn|
        puts "Turn #{turn.turn_number}:"
        puts "  Input: #{turn.task.truncate(60)}"
        if turn.task != turn.resolved_task
          puts "  Resolved: #{turn.resolved_task.truncate(60)}"
        end
        puts "  Score: #{turn.score.round(2)}/10"
        if turn.suggestions.any?
          puts "  Suggestions: #{turn.suggestions.length} available"
        end
        puts ""
      end
    end

    sig { void }
    def clear_conversation
      @conversation_memory.clear
      puts "\nConversation history cleared.\n"
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
