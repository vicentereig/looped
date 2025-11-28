# typed: strict
# frozen_string_literal: true

module Looped
  class Agent
    extend T::Sig

    DEFAULT_MODEL = 'openai/gpt-4o-mini'
    DEFAULT_MAX_ITERATIONS = 10

    sig { returns(DSPy::ReAct) }
    attr_reader :react

    sig { returns(Memory) }
    attr_reader :memory

    sig { returns(State) }
    attr_reader :state

    sig { returns(Judge) }
    attr_reader :judge

    sig { returns(T.nilable(String)) }
    attr_reader :instructions_mtime

    sig { params(model: T.nilable(String), max_iterations: Integer, judge_model: T.nilable(String)).void }
    def initialize(model: nil, max_iterations: DEFAULT_MAX_ITERATIONS, judge_model: nil)
      @model_id = T.let(model || ENV.fetch('LOOPED_MODEL', DEFAULT_MODEL), String)
      @max_iterations = T.let(max_iterations, Integer)
      @memory = T.let(Memory.new, Memory)
      @state = T.let(State.new, State)
      @judge = T.let(Judge.new(model: judge_model), Judge)
      @instructions_mtime = T.let(nil, T.nilable(String))

      # Build the ReAct agent with tools
      @react = T.let(build_react_agent, DSPy::ReAct)

      # Load any existing instructions
      maybe_reload_instructions
    end

    sig { params(task: String, context: String).returns(Types::TrainingResult) }
    def run(task:, context: '')
      # Check for instruction hot-reload
      maybe_reload_instructions

      # Clear memory for new task
      @memory.clear

      # Execute the agent
      result = execute_task(task: task, context: context)

      # Judge the result
      judgment = @judge.evaluate(task: task, solution: result[:solution])

      # Create training result
      training_result = Types::TrainingResult.new(
        task: task,
        solution: result[:solution],
        score: judgment.score,
        feedback: @judge.to_feedback(judgment),
        timestamp: Time.now.utc.iso8601
      )

      # Persist for GEPA optimization
      @state.append_training_result(training_result)

      training_result
    end

    sig { void }
    def reload_instructions
      instructions = @state.load_instructions
      return unless instructions

      # Create a new react agent with the updated instructions
      thought_instruction = instructions.thought_generator
      observation_instruction = instructions.observation_processor

      if thought_instruction || observation_instruction
        @react = build_react_agent(
          thought_instruction: thought_instruction,
          observation_instruction: observation_instruction
        )

        # Track mtime for hot-reload detection
        @instructions_mtime = instructions.updated_at
      end
    end

    private

    sig { params(thought_instruction: T.nilable(String), observation_instruction: T.nilable(String)).returns(DSPy::ReAct) }
    def build_react_agent(thought_instruction: nil, observation_instruction: nil)
      # Configure DSPy with our model
      DSPy.configure do |config|
        config.lm = DSPy::LM.new(@model_id, api_key: resolve_api_key(@model_id))
      end

      # Build tools
      tools = [
        Tools::ReadFile.new,
        Tools::WriteFile.new,
        Tools::SearchCode.new,
        Tools::RunCommand.new
      ]

      # Create base ReAct agent
      agent = DSPy::ReAct.new(
        Looped::CodingTaskSignature,
        tools: tools,
        max_iterations: @max_iterations
      )

      # Apply custom instructions if present
      if thought_instruction
        agent = agent.with_instruction(thought_instruction)
      end

      agent
    end

    sig { params(task: String, context: String).returns(T::Hash[Symbol, T.untyped]) }
    def execute_task(task:, context:)
      # Build history from memory for context
      history = @memory.to_context

      # Run ReAct
      result = @react.forward(
        task: task,
        context: context,
        history: history
      )

      # Record actions in memory
      result.history.each do |entry|
        # Normalize action_input to a hash
        action_input = entry[:action_input]
        action_input = case action_input
                       when Hash then action_input
                       when String then { 'input' => action_input }
                       when NilClass then {}
                       else { 'value' => action_input.to_s }
                       end

        @memory.add(
          action_type: entry[:action] || 'unknown',
          action_input: action_input,
          action_output: entry[:observation]&.to_s || '',
          model_id: @model_id
        )
      end

      {
        solution: result.solution,
        files_modified: result.files_modified,
        iterations: result.iterations,
        tools_used: result.tools_used
      }
    end

    sig { void }
    def maybe_reload_instructions
      instructions = @state.load_instructions
      return unless instructions

      # Reload if mtime changed
      if @instructions_mtime != instructions.updated_at
        reload_instructions
      end
    end

    sig { params(model_id: String).returns(T.nilable(String)) }
    def resolve_api_key(model_id)
      provider = model_id.split('/').first
      case provider
      when 'openai'
        ENV['OPENAI_API_KEY']
      when 'anthropic'
        ENV['ANTHROPIC_API_KEY']
      when 'gemini', 'google'
        ENV['GEMINI_API_KEY']
      else
        ENV['OPENAI_API_KEY']
      end
    end
  end
end
