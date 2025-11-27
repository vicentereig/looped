# typed: strict
# frozen_string_literal: true

require 'async'

module Looped
  class Optimizer
    extend T::Sig

    DEFAULT_BATCH_SIZE = 5
    DEFAULT_MAX_METRIC_CALLS = 32
    DEFAULT_CHECK_INTERVAL = 60

    sig { returns(State) }
    attr_reader :state

    sig { returns(T::Boolean) }
    attr_reader :running

    sig do
      params(
        state: State,
        batch_size: Integer,
        max_metric_calls: Integer,
        check_interval: Integer,
        reflection_model: T.nilable(String)
      ).void
    end
    def initialize(
      state:,
      batch_size: DEFAULT_BATCH_SIZE,
      max_metric_calls: DEFAULT_MAX_METRIC_CALLS,
      check_interval: DEFAULT_CHECK_INTERVAL,
      reflection_model: nil
    )
      @state = state
      @batch_size = batch_size
      @max_metric_calls = max_metric_calls
      @check_interval = check_interval
      @reflection_model = T.let(
        reflection_model || ENV.fetch('LOOPED_REFLECTION_MODEL', 'gpt-4o-mini'),
        String
      )
      @running = T.let(false, T::Boolean)
    end

    sig { void }
    def start
      @running = true

      Async do |task|
        while @running
          check_and_optimize
          task.sleep(@check_interval)
        end
      end
    end

    sig { void }
    def stop
      @running = false
    end

    sig { void }
    def check_and_optimize
      buffer = @state.peek_training_buffer
      return if buffer.length < @batch_size

      optimize(buffer)
    end

    sig { params(training_results: T::Array[Types::TrainingResult]).void }
    def optimize(training_results)
      # Build trainset from training results
      trainset = build_trainset(training_results)
      return if trainset.empty?

      # Load current instructions
      current_instructions = @state.load_instructions

      # Build the base agent for optimization
      agent = build_agent_for_optimization(current_instructions)

      # Configure GEPA metric
      metric = build_metric

      # Create reflection LM for GEPA
      reflection_lm = DSPy::ReflectionLM.new(model: @reflection_model)

      # Build feedback map for multi-predictor optimization
      feedback_map = build_feedback_map

      # Run GEPA optimization
      gepa = DSPy::Teleprompt::GEPA.new(
        metric: metric,
        reflection_lm: reflection_lm,
        feedback_map: feedback_map,
        config: {
          max_metric_calls: @max_metric_calls,
          minibatch_size: [@batch_size, trainset.length].min,
          perfect_score: 10.0,
          skip_perfect_score: true,
          use_merge: trainset.length >= 4
        }
      )

      result = gepa.compile(agent.react, trainset: trainset)

      # Extract optimized instructions from the best program
      save_optimized_instructions(result, current_instructions)

      # Consume the training buffer after successful optimization
      @state.consume_training_buffer
    end

    private

    sig { params(training_results: T::Array[Types::TrainingResult]).returns(T::Array[DSPy::Example]) }
    def build_trainset(training_results)
      training_results.map do |result|
        DSPy::Example.new(
          input_values: {
            task: result.task,
            context: '',
            history: []
          },
          expected: {
            solution: result.solution
          },
          metadata: {
            score: result.score,
            feedback: result.feedback
          }
        )
      end
    end

    sig { params(instructions: T.nilable(Types::Instructions)).returns(Agent) }
    def build_agent_for_optimization(instructions)
      agent = Agent.new

      # Apply existing instructions if present
      if instructions
        agent.reload_instructions
      end

      agent
    end

    sig { returns(T.proc.params(arg0: DSPy::Example, arg1: T.untyped).returns(T::Hash[Symbol, T.untyped])) }
    def build_metric
      lambda do |example, prediction|
        # Extract the pre-computed score and feedback from metadata
        metadata = example.metadata || {}
        score = metadata[:score] || 0.0
        feedback = metadata[:feedback] || ''

        # Return score + feedback for GEPA reflection
        { score: score, feedback: feedback }
      end
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def build_feedback_map
      # Provide feedback functions for each predictor in ReAct
      {
        'thought_generator' => lambda do |predictor_output:, predictor_inputs:, module_inputs:, module_outputs:, captured_trace:|
          metadata = module_inputs.metadata || {}
          feedback = metadata[:feedback] || ''
          score = metadata[:score] || 0.0

          # Filter feedback to focus on thought generation quality
          thought_feedback = extract_thought_feedback(feedback)

          { score: score, feedback: thought_feedback }
        end,
        'observation_processor' => lambda do |predictor_output:, predictor_inputs:, module_inputs:, module_outputs:, captured_trace:|
          metadata = module_inputs.metadata || {}
          feedback = metadata[:feedback] || ''
          score = metadata[:score] || 0.0

          # Filter feedback to focus on observation processing
          observation_feedback = extract_observation_feedback(feedback)

          { score: score, feedback: observation_feedback }
        end
      }
    end

    sig { params(feedback: String).returns(String) }
    def extract_thought_feedback(feedback)
      # Extract feedback relevant to reasoning and planning
      lines = feedback.lines.select do |line|
        line.match?(/reason|think|plan|approach|logic|decision/i) ||
          line.match?(/score|critique|suggestion/i)
      end

      lines.empty? ? feedback : lines.join
    end

    sig { params(feedback: String).returns(String) }
    def extract_observation_feedback(feedback)
      # Extract feedback relevant to observation interpretation
      lines = feedback.lines.select do |line|
        line.match?(/observ|interpret|understand|result|output/i) ||
          line.match?(/score|critique|suggestion/i)
      end

      lines.empty? ? feedback : lines.join
    end

    sig { params(result: DSPy::Teleprompt::OptimizationResult, current: T.nilable(Types::Instructions)).void }
    def save_optimized_instructions(result, current)
      optimized_program = result.optimized_program

      # Extract instructions from the optimized predictors
      thought_instruction = extract_predictor_instruction(optimized_program, 'thought_generator')
      observation_instruction = extract_predictor_instruction(optimized_program, 'observation_processor')

      # Calculate new generation number
      generation = current ? current.generation + 1 : 1
      best_score = result.best_score_value || 0.0

      # Save to state
      @state.save_instructions(
        instructions: {
          thought_generator: thought_instruction,
          observation_processor: observation_instruction
        },
        score: best_score,
        generation: generation
      )
    end

    sig { params(program: DSPy::Module, predictor_name: String).returns(T.nilable(String)) }
    def extract_predictor_instruction(program, predictor_name)
      predictors = program.named_predictors
      predictor = predictors.find { |name, _| name == predictor_name }&.last

      return nil unless predictor

      if predictor.respond_to?(:prompt) && predictor.prompt.respond_to?(:instruction)
        predictor.prompt.instruction
      elsif predictor.respond_to?(:instruction)
        predictor.instruction
      end
    end
  end
end
