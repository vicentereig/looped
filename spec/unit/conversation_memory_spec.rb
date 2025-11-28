# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Looped::ConversationMemory do
  subject(:memory) { described_class.new(storage_dir: temp_dir, max_turns: 3) }

  let(:temp_dir) { Dir.mktmpdir('looped_test') }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#add_turn' do
    it 'adds a turn with all fields' do
      memory.add_turn(
        task: 'user input',
        resolved_task: 'resolved task',
        solution: 'solution',
        score: 8.5,
        suggestions: ['improve A', 'improve B']
      )

      expect(memory.turn_count).to eq(1)
      expect(memory.last_turn.task).to eq('user input')
      expect(memory.last_turn.resolved_task).to eq('resolved task')
      expect(memory.current_suggestions).to eq(['improve A', 'improve B'])
    end

    it 'increments turn_number automatically' do
      memory.add_turn(task: 'task 1', resolved_task: 'task 1', solution: '', score: 0.0)
      memory.add_turn(task: 'task 2', resolved_task: 'task 2', solution: '', score: 0.0)

      expect(memory.turns[0].turn_number).to eq(1)
      expect(memory.turns[1].turn_number).to eq(2)
    end

    it 'enforces max_turns limit' do
      4.times do |i|
        memory.add_turn(
          task: "task #{i}",
          resolved_task: "task #{i}",
          solution: '',
          score: 0.0
        )
      end

      expect(memory.turn_count).to eq(3)
      expect(memory.turns.first.task).to eq('task 1')
    end

    it 'persists turns to disk' do
      memory.add_turn(
        task: 'persisted task',
        resolved_task: 'persisted resolved',
        solution: 'persisted solution',
        score: 7.5,
        suggestions: ['suggestion 1']
      )

      # Create a new instance to verify persistence
      new_memory = described_class.new(storage_dir: temp_dir)

      expect(new_memory.turn_count).to eq(1)
      expect(new_memory.last_turn.task).to eq('persisted task')
      expect(new_memory.current_suggestions).to eq(['suggestion 1'])
    end

    it 'stores judgment when provided' do
      judgment = Looped::Types::Judgment.new(
        score: 8.0,
        passed: true,
        critique: 'Good work',
        suggestions: ['test it']
      )

      memory.add_turn(
        task: 'input',
        resolved_task: 'resolved',
        solution: 'code',
        score: 8.0,
        suggestions: ['test it'],
        judgment: judgment
      )

      expect(memory.last_turn.judgment).not_to be_nil
      expect(memory.last_turn.judgment.critique).to eq('Good work')
    end
  end

  describe '#to_context' do
    it 'returns empty context when no turns' do
      context = memory.to_context

      expect(context.previous_task).to be_nil
      expect(context.previous_solution_summary).to be_nil
      expect(context.available_suggestions).to eq([])
    end

    it 'returns lean context from last turn' do
      memory.add_turn(
        task: 'input',
        resolved_task: 'Write factorial',
        solution: 'def factorial(n)...',
        score: 8.0,
        suggestions: ['add tests']
      )

      context = memory.to_context

      expect(context.previous_task).to eq('Write factorial')
      expect(context.previous_solution_summary).to eq('def factorial(n)...')
      expect(context.available_suggestions).to eq(['add tests'])
    end

    it 'truncates long solutions in summary' do
      long_solution = 'x' * 300

      memory.add_turn(
        task: 'input',
        resolved_task: 'task',
        solution: long_solution,
        score: 5.0
      )

      context = memory.to_context

      expect(context.previous_solution_summary.length).to eq(201)
      expect(context.previous_solution_summary).to end_with('...')
    end
  end

  describe '#suggestion_at' do
    before do
      memory.add_turn(
        task: '',
        resolved_task: '',
        solution: '',
        score: 0.0,
        suggestions: ['first', 'second', 'third']
      )
    end

    it 'returns suggestion by 1-based index' do
      expect(memory.suggestion_at(1)).to eq('first')
      expect(memory.suggestion_at(2)).to eq('second')
      expect(memory.suggestion_at(3)).to eq('third')
    end

    it 'returns nil for index 0' do
      expect(memory.suggestion_at(0)).to be_nil
    end

    it 'returns nil for out of range index' do
      expect(memory.suggestion_at(4)).to be_nil
      expect(memory.suggestion_at(-1)).to be_nil
    end
  end

  describe '#clear' do
    it 'removes all turns and suggestions' do
      memory.add_turn(
        task: 'task',
        resolved_task: 'task',
        solution: 'solution',
        score: 5.0,
        suggestions: ['suggestion']
      )

      memory.clear

      expect(memory.turn_count).to eq(0)
      expect(memory.current_suggestions).to eq([])
    end

    it 'removes the conversation file' do
      memory.add_turn(
        task: 'task',
        resolved_task: 'task',
        solution: 'solution',
        score: 5.0
      )

      conversation_file = File.join(temp_dir, 'conversation.json')
      expect(File.exist?(conversation_file)).to be true

      memory.clear

      expect(File.exist?(conversation_file)).to be false
    end
  end

  describe 'persistence' do
    it 'survives application restart' do
      # First session
      memory.add_turn(
        task: 'go for 1',
        resolved_task: 'Add error handling',
        solution: 'begin; rescue; end',
        score: 7.5,
        suggestions: ['Add logging', 'Add retries']
      )

      # Second session (new instance)
      new_memory = described_class.new(storage_dir: temp_dir, max_turns: 3)

      expect(new_memory.turn_count).to eq(1)
      expect(new_memory.last_turn.task).to eq('go for 1')
      expect(new_memory.last_turn.resolved_task).to eq('Add error handling')
      expect(new_memory.current_suggestions).to eq(['Add logging', 'Add retries'])
    end

    it 'handles corrupted JSON gracefully' do
      File.write(File.join(temp_dir, 'conversation.json'), 'not valid json')

      new_memory = described_class.new(storage_dir: temp_dir)

      expect(new_memory.turn_count).to eq(0)
      expect(new_memory.current_suggestions).to eq([])
    end

    it 'persists judgment correctly' do
      judgment = Looped::Types::Judgment.new(
        score: 9.0,
        passed: true,
        critique: 'Excellent',
        suggestions: ['minor improvement']
      )

      memory.add_turn(
        task: 'task',
        resolved_task: 'task',
        solution: 'code',
        score: 9.0,
        suggestions: ['minor improvement'],
        judgment: judgment
      )

      new_memory = described_class.new(storage_dir: temp_dir)

      expect(new_memory.last_turn.judgment).not_to be_nil
      expect(new_memory.last_turn.judgment.score).to eq(9.0)
      expect(new_memory.last_turn.judgment.passed).to be true
      expect(new_memory.last_turn.judgment.critique).to eq('Excellent')
    end
  end
end
