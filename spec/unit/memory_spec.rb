# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Looped::Memory do
  subject(:memory) { described_class.new(max_entries: 5) }

  describe '#add' do
    it 'adds an entry with all required fields' do
      memory.add(
        action_type: 'read_file',
        action_input: { path: '/test.rb' },
        action_output: 'file contents'
      )

      expect(memory.entries.length).to eq(1)
      entry = memory.entries.first
      expect(entry.action_type).to eq('read_file')
      expect(entry.action_input).to eq({ path: '/test.rb' })
      expect(entry.action_output).to eq('file contents')
      expect(entry.timestamp).not_to be_nil
    end

    it 'includes optional model_id and tokens_used' do
      memory.add(
        action_type: 'search_code',
        action_input: { pattern: 'def' },
        action_output: 'matches',
        model_id: 'gpt-4o-mini',
        tokens_used: 150
      )

      entry = memory.entries.first
      expect(entry.model_id).to eq('gpt-4o-mini')
      expect(entry.tokens_used).to eq(150)
    end

    it 'tracks errors when provided' do
      memory.add(
        action_type: 'run_command',
        action_input: { command: 'exit 1' },
        action_output: '',
        error: 'Command failed'
      )

      entry = memory.entries.first
      expect(entry.error).to eq('Command failed')
    end

    it 'enforces max_entries limit' do
      6.times do |i|
        memory.add(
          action_type: "action_#{i}",
          action_input: {},
          action_output: "output_#{i}"
        )
      end

      expect(memory.entries.length).to eq(5)
      expect(memory.entries.first.action_type).to eq('action_1')
      expect(memory.entries.last.action_type).to eq('action_5')
    end
  end

  describe '#to_context' do
    it 'returns empty array when no entries' do
      expect(memory.to_context).to eq([])
    end

    it 'returns ActionSummary structs with truncated output' do
      memory.add(
        action_type: 'read_file',
        action_input: { path: '/test.rb' },
        action_output: 'a' * 1000
      )

      context = memory.to_context
      expect(context.length).to eq(1)
      expect(context.first).to be_a(Looped::Types::ActionSummary)
      expect(context.first.action).to eq('read_file')
      expect(context.first.result.length).to be <= 503 # 500 + '...'
    end

    it 'formats action with summarized input' do
      memory.add(
        action_type: 'write_file',
        action_input: { path: '/output.rb', content: 'puts "hello"' },
        action_output: 'Success'
      )

      context = memory.to_context
      expect(context.first.action).to include('write_file')
    end
  end

  describe '#clear' do
    it 'removes all entries' do
      memory.add(
        action_type: 'test',
        action_input: {},
        action_output: 'output'
      )

      memory.clear
      expect(memory.entries).to be_empty
    end
  end

  describe '#recent' do
    before do
      3.times do |i|
        memory.add(
          action_type: "action_#{i}",
          action_input: {},
          action_output: "output_#{i}"
        )
      end
    end

    it 'returns the most recent n entries' do
      recent = memory.recent(2)
      expect(recent.length).to eq(2)
      expect(recent.first.action_type).to eq('action_1')
      expect(recent.last.action_type).to eq('action_2')
    end

    it 'returns all entries if n exceeds count' do
      recent = memory.recent(10)
      expect(recent.length).to eq(3)
    end
  end
end
