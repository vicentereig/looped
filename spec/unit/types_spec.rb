# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Looped::Types' do
  describe Looped::Types::MemoryEntry do
    it 'creates a valid entry with required fields' do
      entry = described_class.new(
        action_type: 'read_file',
        action_input: { path: '/test.rb' },
        action_output: 'contents',
        timestamp: '2024-01-01T10:00:00Z'
      )

      expect(entry.action_type).to eq('read_file')
      expect(entry.action_input).to eq({ path: '/test.rb' })
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
end
