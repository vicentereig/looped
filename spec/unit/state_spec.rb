# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Looped::State do
  # Use the temp dir set by spec_helper via ENV['LOOPED_STORAGE_DIR']
  subject(:state) { described_class.new }

  describe '#initialize' do
    it 'creates storage directories' do
      new_state = described_class.new
      expect(Dir.exist?(new_state.storage_dir)).to be true
      expect(Dir.exist?(File.join(new_state.storage_dir, 'history'))).to be true
    end
  end

  describe '#save_instructions and #load_instructions' do
    it 'persists and loads instructions' do
      state.save_instructions(
        instructions: {
          thought_generator: 'Think carefully',
          observation_processor: 'Process thoroughly'
        },
        score: 8.5,
        generation: 3
      )

      loaded = state.load_instructions

      expect(loaded).to be_a(Looped::Types::Instructions)
      expect(loaded.thought_generator).to eq('Think carefully')
      expect(loaded.observation_processor).to eq('Process thoroughly')
      expect(loaded.score).to eq(8.5)
      expect(loaded.generation).to eq(3)
      expect(loaded.updated_at).not_to be_nil
    end

    it 'returns nil when no instructions exist' do
      expect(state.load_instructions).to be_nil
    end

    it 'handles nil instruction values' do
      state.save_instructions(
        instructions: {
          thought_generator: nil,
          observation_processor: 'Only this one'
        },
        score: 5.0,
        generation: 1
      )

      loaded = state.load_instructions
      expect(loaded.thought_generator).to be_nil
      expect(loaded.observation_processor).to eq('Only this one')
    end
  end

  describe 'training buffer operations' do
    let(:result1) do
      Looped::Types::TrainingResult.new(
        task: 'Fix bug in parser',
        solution: 'Updated regex',
        score: 7.5,
        feedback: 'Good solution',
        timestamp: '2024-01-01T10:00:00Z'
      )
    end

    let(:result2) do
      Looped::Types::TrainingResult.new(
        task: 'Add feature',
        solution: 'New module',
        score: 9.0,
        feedback: 'Excellent',
        timestamp: '2024-01-01T11:00:00Z'
      )
    end

    describe '#append_training_result' do
      it 'adds a training result to the buffer' do
        state.append_training_result(result1)

        buffer = state.peek_training_buffer
        expect(buffer.length).to eq(1)
        expect(buffer.first.task).to eq('Fix bug in parser')
      end

      it 'appends multiple results' do
        state.append_training_result(result1)
        state.append_training_result(result2)

        buffer = state.peek_training_buffer
        expect(buffer.length).to eq(2)
      end
    end

    describe '#peek_training_buffer' do
      it 'returns empty array when no results' do
        expect(state.peek_training_buffer).to eq([])
      end

      it 'does not clear the buffer' do
        state.append_training_result(result1)

        state.peek_training_buffer
        state.peek_training_buffer

        expect(state.peek_training_buffer.length).to eq(1)
      end
    end

    describe '#consume_training_buffer' do
      before do
        state.append_training_result(result1)
        state.append_training_result(result2)
      end

      it 'returns all buffered results' do
        consumed = state.consume_training_buffer
        expect(consumed.length).to eq(2)
        expect(consumed.first.task).to eq('Fix bug in parser')
        expect(consumed.last.task).to eq('Add feature')
      end

      it 'clears the buffer after consuming' do
        state.consume_training_buffer
        expect(state.peek_training_buffer).to be_empty
      end

      it 'archives consumed results to history' do
        state.consume_training_buffer

        history_files = Dir.glob(File.join(state.storage_dir, 'history', '*.json'))
        expect(history_files.length).to eq(1)
      end

      it 'returns empty array when buffer is empty' do
        state.consume_training_buffer
        expect(state.consume_training_buffer).to eq([])
      end
    end
  end

  describe '#storage_dir' do
    it 'returns the storage directory path from environment' do
      expect(state.storage_dir).to eq(ENV['LOOPED_STORAGE_DIR'])
    end

    it 'accepts custom storage_dir in constructor' do
      Dir.mktmpdir('custom_looped') do |custom_dir|
        custom_state = described_class.new(storage_dir: custom_dir)
        expect(custom_state.storage_dir).to eq(custom_dir)
      end
    end
  end
end
