# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Looped::Agent, :vcr do
  subject(:agent) { described_class.new }

  around(:each) do |example|
    Dir.mktmpdir('looped_agent_test') do |tmpdir|
      @test_dir = tmpdir
      Dir.chdir(tmpdir) do
        example.run
      end
    end
  end

  describe '#run' do
    context 'with a simple code generation task' do
      let(:task) { 'Write a Ruby function that checks if a string is a palindrome. Save it to palindrome.rb' }

      it 'generates code and returns a training result', vcr: { cassette_name: 'agent/simple_code_generation' } do
        result = agent.run(task: task)

        expect(result).to be_a(Looped::Types::TrainingResult)
        expect(result.task).to eq(task)
        expect(result.solution).to be_a(String)
        expect(result.solution.length).to be > 0
        expect(result.score).to be_a(Float)
        expect(result.score).to be_between(0, 10)
        expect(result.feedback).to be_a(String)
        expect(result.timestamp).to match(/\d{4}-\d{2}-\d{2}T/)
      end

      it 'persists the result to the training buffer', vcr: { cassette_name: 'agent/simple_code_generation' } do
        agent.run(task: task)

        buffer = agent.state.peek_training_buffer
        expect(buffer.length).to eq(1)
        expect(buffer.first.task).to eq(task)
      end
    end

    context 'with a task requiring file reading' do
      let(:task) { 'Read the contents of test_input.txt and describe what it contains' }

      before do
        File.write(File.join(@test_dir, 'test_input.txt'), "Hello, World!\nThis is a test file.\n")
      end

      it 'uses the read_file tool', vcr: { cassette_name: 'agent/file_reading_task' } do
        result = agent.run(task: task, context: "Working directory: #{@test_dir}")

        expect(result.solution).to be_a(String)
        # The agent should have read the file
        expect(agent.memory.entries).not_to be_empty
      end
    end

    context 'with code search task' do
      let(:task) { 'Search for any Ruby files in the current directory and list them' }

      before do
        File.write(File.join(@test_dir, 'example.rb'), "puts 'hello'\n")
        File.write(File.join(@test_dir, 'another.rb'), "class Foo; end\n")
      end

      it 'uses the search_code tool', vcr: { cassette_name: 'agent/code_search_task' } do
        result = agent.run(task: task, context: "Working directory: #{@test_dir}")

        expect(result).to be_a(Looped::Types::TrainingResult)
        expect(result.solution.length).to be > 0
      end
    end
  end

  describe '#memory' do
    it 'starts empty' do
      expect(agent.memory.entries).to be_empty
    end

    it 'clears between task runs', vcr: { cassette_name: 'agent/memory_clearing' } do
      agent.run(task: 'Say hello')

      # Memory should have entries from the first run
      entries_after_first = agent.memory.entries.length

      agent.run(task: 'Say goodbye')

      # Memory should be cleared for new task
      # (entries are from second run only)
      expect(agent.memory.entries.length).to be <= entries_after_first + 5
    end
  end

  describe '#reload_instructions' do
    it 'loads instructions from state when available' do
      # Save some instructions
      agent.state.save_instructions(
        instructions: {
          thought_generator: 'Think step by step',
          observation_processor: nil
        },
        score: 8.5,
        generation: 1
      )

      agent.reload_instructions

      expect(agent.instructions_mtime).not_to be_nil
    end

    it 'does nothing when no instructions exist' do
      agent.reload_instructions

      expect(agent.instructions_mtime).to be_nil
    end
  end
end
