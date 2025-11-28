# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Looped::Types' do
  describe Looped::Types::MemoryEntry do
    it 'creates a valid entry with required fields' do
      entry = described_class.new(
        action_type: 'read_file',
        action_input: { 'path' => '/test.rb' },
        action_output: 'contents',
        timestamp: '2024-01-01T10:00:00Z'
      )

      expect(entry.action_type).to eq('read_file')
      expect(entry.action_input).to eq({ 'path' => '/test.rb' })
      expect(entry.action_output).to eq('contents')
      expect(entry.timestamp).to eq('2024-01-01T10:00:00Z')
    end

    it 'allows optional fields' do
      entry = described_class.new(
        action_type: 'run_command',
        action_input: {},
        action_output: '',
        timestamp: '2024-01-01T10:00:00Z',
        model_id: 'gpt-4o',
        error: 'timeout',
        tokens_used: 100
      )

      expect(entry.model_id).to eq('gpt-4o')
      expect(entry.error).to eq('timeout')
      expect(entry.tokens_used).to eq(100)
    end
  end

  describe Looped::Types::ActionSummary do
    it 'creates a valid summary' do
      summary = described_class.new(
        action: 'read_file(/test.rb)',
        result: 'File contents...'
      )

      expect(summary.action).to eq('read_file(/test.rb)')
      expect(summary.result).to eq('File contents...')
    end
  end

  describe Looped::Types::TrainingResult do
    it 'creates a valid training result' do
      result = described_class.new(
        task: 'Fix the bug',
        solution: 'Updated the code',
        score: 8.5,
        feedback: 'Good work',
        timestamp: '2024-01-01T10:00:00Z'
      )

      expect(result.task).to eq('Fix the bug')
      expect(result.solution).to eq('Updated the code')
      expect(result.score).to eq(8.5)
      expect(result.feedback).to eq('Good work')
      expect(result.timestamp).to eq('2024-01-01T10:00:00Z')
    end
  end

  describe Looped::Types::Instructions do
    it 'creates instructions with defaults' do
      instructions = described_class.new(
        updated_at: '2024-01-01T10:00:00Z'
      )

      expect(instructions.thought_generator).to be_nil
      expect(instructions.observation_processor).to be_nil
      expect(instructions.score).to eq(0.0)
      expect(instructions.generation).to eq(0)
    end

    it 'accepts custom instruction values' do
      instructions = described_class.new(
        thought_generator: 'Think step by step',
        observation_processor: 'Analyze carefully',
        score: 9.0,
        generation: 5,
        updated_at: '2024-01-01T10:00:00Z'
      )

      expect(instructions.thought_generator).to eq('Think step by step')
      expect(instructions.observation_processor).to eq('Analyze carefully')
      expect(instructions.score).to eq(9.0)
      expect(instructions.generation).to eq(5)
    end
  end

  describe Looped::Types::Judgment do
    it 'creates a judgment with defaults' do
      judgment = described_class.new(
        score: 7.5,
        passed: true,
        critique: 'Good solution'
      )

      expect(judgment.score).to eq(7.5)
      expect(judgment.passed).to be true
      expect(judgment.critique).to eq('Good solution')
      expect(judgment.suggestions).to eq([])
    end

    it 'accepts suggestions array' do
      judgment = described_class.new(
        score: 6.0,
        passed: false,
        critique: 'Needs improvement',
        suggestions: ['Add error handling', 'Improve naming']
      )

      expect(judgment.suggestions).to eq(['Add error handling', 'Improve naming'])
    end
  end

  describe Looped::Types::Intent do
    it 'has all expected values' do
      expect(Looped::Types::Intent::NewTask.serialize).to eq('new_task')
      expect(Looped::Types::Intent::FollowUp.serialize).to eq('follow_up')
      expect(Looped::Types::Intent::SelectSuggestion.serialize).to eq('select_suggestion')
    end

    it 'can deserialize from string' do
      expect(Looped::Types::Intent.deserialize('new_task')).to eq(Looped::Types::Intent::NewTask)
      expect(Looped::Types::Intent.deserialize('follow_up')).to eq(Looped::Types::Intent::FollowUp)
      expect(Looped::Types::Intent.deserialize('select_suggestion')).to eq(Looped::Types::Intent::SelectSuggestion)
    end
  end

  describe Looped::Types::ConversationTurn do
    it 'creates a valid turn with required fields' do
      turn = described_class.new(
        task: 'go for 1',
        resolved_task: 'Add error handling',
        solution: 'def foo; rescue; end',
        score: 8.0,
        timestamp: '2024-01-01T10:00:00Z',
        turn_number: 1
      )

      expect(turn.task).to eq('go for 1')
      expect(turn.resolved_task).to eq('Add error handling')
      expect(turn.solution).to eq('def foo; rescue; end')
      expect(turn.score).to eq(8.0)
      expect(turn.suggestions).to eq([])
      expect(turn.judgment).to be_nil
      expect(turn.turn_number).to eq(1)
    end

    it 'accepts optional suggestions and judgment' do
      judgment = Looped::Types::Judgment.new(
        score: 8.0,
        passed: true,
        critique: 'Good',
        suggestions: ['test it']
      )

      turn = described_class.new(
        task: 'Write factorial',
        resolved_task: 'Write factorial',
        solution: 'def factorial(n)...',
        score: 8.0,
        suggestions: ['Add memoization', 'Add validation'],
        judgment: judgment,
        timestamp: '2024-01-01T10:00:00Z',
        turn_number: 2
      )

      expect(turn.suggestions).to eq(['Add memoization', 'Add validation'])
      expect(turn.judgment).to eq(judgment)
    end
  end

  describe Looped::Types::ConversationContext do
    it 'creates empty context with defaults' do
      context = described_class.new

      expect(context.previous_task).to be_nil
      expect(context.previous_solution_summary).to be_nil
      expect(context.available_suggestions).to eq([])
    end

    it 'creates context with all fields' do
      context = described_class.new(
        previous_task: 'Write factorial',
        previous_solution_summary: 'def factorial(n)...',
        available_suggestions: ['Add tests', 'Add validation']
      )

      expect(context.previous_task).to eq('Write factorial')
      expect(context.previous_solution_summary).to eq('def factorial(n)...')
      expect(context.available_suggestions).to eq(['Add tests', 'Add validation'])
    end
  end

  describe Looped::Types::IntentClassification do
    it 'creates a valid classification' do
      classification = described_class.new(
        intent: Looped::Types::Intent::SelectSuggestion,
        resolved_task: 'Add error handling',
        suggestion_index: 1,
        confidence: 0.95,
        reasoning: 'User referenced suggestion #1'
      )

      expect(classification.intent).to eq(Looped::Types::Intent::SelectSuggestion)
      expect(classification.resolved_task).to eq('Add error handling')
      expect(classification.suggestion_index).to eq(1)
      expect(classification.confidence).to eq(0.95)
      expect(classification.reasoning).to eq('User referenced suggestion #1')
    end

    it 'allows nil suggestion_index for non-selection intents' do
      classification = described_class.new(
        intent: Looped::Types::Intent::NewTask,
        resolved_task: 'Write a sorting function',
        suggestion_index: nil,
        confidence: 0.9,
        reasoning: 'New unrelated task'
      )

      expect(classification.suggestion_index).to be_nil
    end
  end
end
