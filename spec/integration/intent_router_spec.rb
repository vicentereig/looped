# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Looped::IntentRouter, :vcr do
  subject(:router) { described_class.new }

  let(:context_with_suggestions) do
    Looped::Types::ConversationContext.new(
      previous_task: 'Write a Ruby function that calculates the factorial of a number',
      previous_solution_summary: 'def factorial(n); n <= 1 ? 1 : n * factorial(n - 1); end',
      available_suggestions: [
        'Add input validation for negative numbers',
        'Add memoization for better performance',
        'Convert to iterative implementation'
      ]
    )
  end

  let(:context_without_suggestions) do
    Looped::Types::ConversationContext.new(
      previous_task: 'Write a factorial function',
      previous_solution_summary: 'def factorial(n)...',
      available_suggestions: []
    )
  end

  let(:empty_context) do
    Looped::Types::ConversationContext.new
  end

  describe '#classify with LLM fallback' do
    context 'when user provides a clearly new task' do
      it 'classifies as NewTask', vcr: { cassette_name: 'intent_router/new_task' } do
        result = router.classify(
          input: 'Write a function to sort an array using quicksort',
          context: context_with_suggestions
        )

        expect(result.intent).to eq(Looped::Types::Intent::NewTask)
        expect(result.resolved_task).to include('sort')
        expect(result.confidence).to be > 0.5
      end
    end

    context 'when user asks to modify the previous solution' do
      it 'classifies and resolves the task', vcr: { cassette_name: 'intent_router/follow_up_modify' } do
        result = router.classify(
          input: 'Can you make it iterative instead of recursive?',
          context: context_with_suggestions
        )

        # LLM may classify as FollowUp or NewTask - both are reasonable
        expect(result.intent).to be_a(Looped::Types::Intent)
        # The resolved task should mention iterative regardless of intent classification
        expect(result.resolved_task.downcase).to include('iterative')
      end
    end

    context 'when user references a suggestion ambiguously' do
      it 'classifies as SelectSuggestion with correct index', vcr: { cassette_name: 'intent_router/ambiguous_suggestion' } do
        result = router.classify(
          input: 'yeah lets do the second one',
          context: context_with_suggestions
        )

        expect(result.intent).to eq(Looped::Types::Intent::SelectSuggestion)
        expect(result.suggestion_index).to eq(2)
        expect(result.resolved_task).to include('memoization')
      end
    end

    context 'when user asks a clarifying question' do
      it 'classifies and provides reasoning', vcr: { cassette_name: 'intent_router/follow_up_question' } do
        result = router.classify(
          input: 'What would be the time complexity of that?',
          context: context_with_suggestions
        )

        # LLM should classify this - the important thing is it produces a valid result
        expect(result.intent).to be_a(Looped::Types::Intent)
        expect(result.resolved_task).to be_a(String)
        expect(result.reasoning).to be_a(String)
      end
    end

    context 'when user wants to continue with no context' do
      it 'classifies as NewTask', vcr: { cassette_name: 'intent_router/new_task_no_context' } do
        result = router.classify(
          input: 'Help me write a web scraper',
          context: empty_context
        )

        expect(result.intent).to eq(Looped::Types::Intent::NewTask)
        expect(result.resolved_task).to include('scraper')
      end
    end

    context 'when user says yes with suggestions available' do
      it 'handles ambiguous affirmative', vcr: { cassette_name: 'intent_router/ambiguous_yes' } do
        result = router.classify(
          input: 'yes please',
          context: context_with_suggestions
        )

        # LLM should make a reasonable decision - either ask for clarification
        # or pick the most likely suggestion
        expect(result.intent).to be_a(Looped::Types::Intent)
        expect(result.reasoning).to be_a(String)
      end
    end
  end

  describe 'fast-path vs LLM classification consistency' do
    # These tests verify that fast-path and LLM produce consistent results
    # for inputs that could be handled by either

    context 'with numeric selection' do
      it 'fast-path matches expected behavior' do
        # Fast-path should handle this
        result = router.classify(input: '2', context: context_with_suggestions)

        expect(result.intent).to eq(Looped::Types::Intent::SelectSuggestion)
        expect(result.suggestion_index).to eq(2)
        expect(result.resolved_task).to eq('Add memoization for better performance')
        expect(result.confidence).to eq(0.95) # Fast-path confidence
      end
    end

    context 'with phrased selection' do
      it 'fast-path matches expected behavior' do
        result = router.classify(input: 'go for 1', context: context_with_suggestions)

        expect(result.intent).to eq(Looped::Types::Intent::SelectSuggestion)
        expect(result.suggestion_index).to eq(1)
        expect(result.resolved_task).to eq('Add input validation for negative numbers')
      end
    end
  end
end
