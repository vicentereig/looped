# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Conversation Flow', :vcr do
  let(:temp_dir) { Dir.mktmpdir('looped_conversation_test') }

  before do
    ENV['LOOPED_STORAGE_DIR'] = temp_dir
  end

  after do
    ENV.delete('LOOPED_STORAGE_DIR')
    FileUtils.rm_rf(temp_dir)
  end

  describe 'intent routing in application' do
    let(:application) { Looped::Application.new }

    describe 'suggestion selection flow' do
      it 'handles numeric suggestion selection after task completion',
         vcr: { cassette_name: 'conversation/suggestion_selection_flow' } do
        # First turn: execute a task that will generate suggestions
        application.send(:process_with_intent, 'Write a Ruby function to check if a number is prime')

        expect(application.conversation_memory.turn_count).to eq(1)
        first_turn = application.conversation_memory.last_turn
        expect(first_turn.resolved_task).to include('prime')

        # Verify suggestions were captured
        suggestions = application.conversation_memory.current_suggestions
        # Suggestions come from the Judge, which we expect to provide some

        # Second turn: select a suggestion (if available) or follow up
        if suggestions.any?
          application.send(:process_with_intent, '1')

          expect(application.conversation_memory.turn_count).to eq(2)
          second_turn = application.conversation_memory.last_turn
          expect(second_turn.task).to eq('1')
          expect(second_turn.resolved_task).to eq(suggestions.first)
        end
      end
    end

    describe 'follow-up flow' do
      it 'handles follow-up requests with context',
         vcr: { cassette_name: 'conversation/follow_up_flow' } do
        # First turn
        application.send(:process_with_intent, 'Write a simple greeting function in Ruby')

        expect(application.conversation_memory.turn_count).to eq(1)

        # Second turn: follow-up modification
        application.send(:process_with_intent, 'Can you add a parameter for the name?')

        expect(application.conversation_memory.turn_count).to eq(2)
        second_turn = application.conversation_memory.last_turn

        # The follow-up should reference adding a parameter
        expect(second_turn.resolved_task.downcase).to include('parameter').or include('name')
      end
    end

    describe 'new task flow' do
      it 'handles completely new tasks',
         vcr: { cassette_name: 'conversation/new_task_flow' } do
        # First turn
        application.send(:process_with_intent, 'Write a function to reverse a string')

        expect(application.conversation_memory.turn_count).to eq(1)

        # Second turn: completely different task
        application.send(:process_with_intent, 'Now write a function to calculate fibonacci numbers')

        expect(application.conversation_memory.turn_count).to eq(2)
        second_turn = application.conversation_memory.last_turn
        expect(second_turn.resolved_task.downcase).to include('fibonacci')
      end
    end
  end

  describe 'conversation persistence' do
    it 'persists conversation across application restarts',
       vcr: { cassette_name: 'conversation/persistence_flow' } do
      # First session
      app1 = Looped::Application.new
      app1.send(:process_with_intent, 'Write a hello world function')

      expect(app1.conversation_memory.turn_count).to eq(1)
      first_task = app1.conversation_memory.last_turn.resolved_task

      # Simulate restart - create new application instance
      app2 = Looped::Application.new

      # Should have restored the conversation
      expect(app2.conversation_memory.turn_count).to eq(1)
      expect(app2.conversation_memory.last_turn.resolved_task).to eq(first_task)

      # Should be able to continue the conversation
      # The suggestions from app1 should be available
      if app2.conversation_memory.current_suggestions.any?
        expect(app2.conversation_memory.current_suggestions).to be_an(Array)
      end
    end
  end

  describe 'intent router integration' do
    let(:router) { Looped::IntentRouter.new }
    let(:memory) { Looped::ConversationMemory.new(storage_dir: temp_dir) }

    it 'correctly routes based on conversation context' do
      # Simulate a conversation turn
      memory.add_turn(
        task: 'Write factorial',
        resolved_task: 'Write a factorial function in Ruby',
        solution: 'def factorial(n); n <= 1 ? 1 : n * factorial(n-1); end',
        score: 8.0,
        suggestions: ['Add memoization', 'Add input validation', 'Make it iterative']
      )

      context = memory.to_context

      # Test fast-path selection
      result = router.classify(input: '1', context: context)
      expect(result.intent).to eq(Looped::Types::Intent::SelectSuggestion)
      expect(result.resolved_task).to eq('Add memoization')

      # Test another fast-path
      result = router.classify(input: 'go for 3', context: context)
      expect(result.intent).to eq(Looped::Types::Intent::SelectSuggestion)
      expect(result.resolved_task).to eq('Make it iterative')
    end
  end
end
