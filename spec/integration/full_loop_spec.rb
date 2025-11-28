# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Full Loop Integration', :vcr do
  describe 'GEPA optimization smoke test' do

    context 'when training buffer has enough results' do
      let(:state) { Looped::State.new }

      before do
        6.times do |i|
          result = Looped::Types::TrainingResult.new(
            task: "Write a Ruby function that calculates factorial of #{i + 1}",
            solution: "def factorial(n)\n  n <= 1 ? 1 : n * factorial(n - 1)\nend",
            score: 7.0 + (i * 0.3),
            feedback: "Good recursive implementation. Consider adding input validation.",
            timestamp: Time.now.utc.iso8601
          )
          state.append_training_result(result)
        end
      end

      it 'runs optimization and saves improved instructions', vcr: { cassette_name: 'full_loop/gepa_optimization' } do
        optimizer = Looped::Optimizer.new(
          state: state,
          batch_size: 5,
          max_metric_calls: 8,
          check_interval: 60
        )

        expect(state.peek_training_buffer.length).to eq(6)
        optimizer.check_and_optimize

        instructions = state.load_instructions
        expect(instructions).not_to be_nil
        expect(instructions.generation).to eq(1)
        expect(instructions.score).to be > 0
        expect(state.peek_training_buffer).to be_empty
      end
    end
  end

  describe 'end-to-end task execution with learning' do
    it 'executes a task and stores training result', vcr: { cassette_name: 'full_loop/end_to_end_task' } do
      agent = Looped::Agent.new

      result = agent.run(
        task: 'Write a simple Ruby function that adds two numbers',
        context: ''
      )

      expect(result).to be_a(Looped::Types::TrainingResult)
      expect(result.task).to include('adds two numbers')
      expect(result.solution).to be_a(String)
      expect(result.score).to be_between(0, 10)
      expect(result.timestamp).not_to be_empty

      # Verify it was stored in training buffer
      state = agent.state
      buffer = state.peek_training_buffer
      expect(buffer.length).to eq(1)
      expect(buffer.first.task).to eq(result.task)
    end
  end

  describe 'training buffer accumulation' do
    it 'accumulates multiple task results' do
      # Create fresh state in isolated temp dir
      state = Looped::State.new

      # Verify buffer starts empty
      expect(state.peek_training_buffer).to be_empty

      3.times do |i|
        result = Looped::Types::TrainingResult.new(
          task: "Task #{i + 1}",
          solution: "Solution #{i + 1}",
          score: 5.0 + i,
          feedback: "Feedback #{i + 1}",
          timestamp: Time.now.utc.iso8601
        )
        state.append_training_result(result)
      end

      buffer = state.peek_training_buffer
      expect(buffer.length).to eq(3)
      expect(buffer.map(&:task)).to eq(['Task 1', 'Task 2', 'Task 3'])
    end

    it 'archives buffer when consumed' do
      state = Looped::State.new
      storage_dir = ENV['LOOPED_STORAGE_DIR']

      result = Looped::Types::TrainingResult.new(
        task: 'Test task',
        solution: 'Test solution',
        score: 7.5,
        feedback: 'Good work',
        timestamp: Time.now.utc.iso8601
      )
      state.append_training_result(result)

      # Peek should show the result
      expect(state.peek_training_buffer.length).to eq(1)

      # Consume should return and clear
      consumed = state.consume_training_buffer
      expect(consumed.length).to eq(1)
      expect(consumed.first.task).to eq('Test task')

      # Buffer should now be empty
      expect(state.peek_training_buffer).to be_empty

      # History directory should have archive
      history_dir = File.join(storage_dir, 'history')
      expect(Dir.glob(File.join(history_dir, '*.json'))).not_to be_empty
    end
  end

  describe 'instructions hot-reload' do
    it 'loads instructions on agent initialization' do
      state = Looped::State.new

      # Save some instructions
      state.save_instructions(
        instructions: {
          thought_generator: 'Think carefully about each step.',
          observation_processor: nil
        },
        score: 8.0,
        generation: 5
      )

      # Create agent - should load instructions
      agent = Looped::Agent.new

      # Agent should have loaded the instructions
      expect(agent.instructions_mtime).not_to be_nil
    end

    it 'detects instruction changes' do
      state = Looped::State.new

      # Create agent with no instructions
      agent = Looped::Agent.new
      initial_mtime = agent.instructions_mtime

      # Save new instructions
      state.save_instructions(
        instructions: {
          thought_generator: 'New instruction',
          observation_processor: nil
        },
        score: 9.0,
        generation: 1
      )

      # Trigger reload check
      agent.reload_instructions

      # Should have updated mtime
      expect(agent.instructions_mtime).not_to eq(initial_mtime)
    end
  end
end
