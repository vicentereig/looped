# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Looped::IntentRouter do
  subject(:router) { described_class.new }

  let(:context_with_suggestions) do
    Looped::Types::ConversationContext.new(
      previous_task: 'Write factorial function',
      previous_solution_summary: 'def factorial(n); n <= 1 ? 1 : n * factorial(n-1); end',
      available_suggestions: ['Add error handling for negative numbers', 'Add memoization', 'Add input validation']
    )
  end

  let(:context_without_suggestions) do
    Looped::Types::ConversationContext.new(
      previous_task: 'Write factorial function',
      previous_solution_summary: 'def factorial(n)...',
      available_suggestions: []
    )
  end

  let(:empty_context) do
    Looped::Types::ConversationContext.new
  end

  describe '#classify (fast-path)' do
    describe 'direct number selection' do
      %w[1 2 3].each do |num|
        it "classifies '#{num}' as SelectSuggestion" do
          result = router.send(:try_fast_classify, num, context_with_suggestions)

          expect(result).not_to be_nil
          expect(result.intent).to eq(Looped::Types::Intent::SelectSuggestion)
          expect(result.suggestion_index).to eq(num.to_i)
          expect(result.confidence).to eq(0.95)
        end
      end

      it 'returns nil for numbers beyond available suggestions' do
        result = router.send(:try_fast_classify, '5', context_with_suggestions)

        expect(result).to be_nil
      end

      it 'returns nil for numbers when no suggestions available' do
        result = router.send(:try_fast_classify, '1', empty_context)

        expect(result).to be_nil
      end
    end

    describe 'phrased selection patterns' do
      [
        'go with 1',
        'go for 2',
        'option 1',
        'suggestion 2',
        'yes 1',
        'yeah 1',
        'do 1',
        'pick 2',
        'choose 1',
        'select 3'
      ].each do |input|
        it "classifies '#{input}' as SelectSuggestion" do
          result = router.send(:try_fast_classify, input, context_with_suggestions)

          expect(result).not_to be_nil
          expect(result.intent).to eq(Looped::Types::Intent::SelectSuggestion)
        end
      end

      it 'extracts correct suggestion index from phrased input' do
        result = router.send(:try_fast_classify, 'go for 2', context_with_suggestions)

        expect(result.suggestion_index).to eq(2)
        expect(result.resolved_task).to eq('Add memoization')
      end
    end

    describe 'ordinal selection patterns' do
      {
        'first' => 1,
        'second' => 2,
        'third' => 3,
        'the first one' => 1,
        'the second suggestion' => 2,
        'first option' => 1
      }.each do |input, expected_index|
        it "classifies '#{input}' as SelectSuggestion with index #{expected_index}" do
          result = router.send(:try_fast_classify, input, context_with_suggestions)

          expect(result).not_to be_nil
          expect(result.intent).to eq(Looped::Types::Intent::SelectSuggestion)
          expect(result.suggestion_index).to eq(expected_index)
        end
      end
    end

    describe 'affirmative responses' do
      %w[yes yeah sure ok okay yep yup].each do |input|
        it "classifies '#{input}' as FollowUp when no suggestions" do
          result = router.send(:try_fast_classify, input, context_without_suggestions)

          expect(result).not_to be_nil
          expect(result.intent).to eq(Looped::Types::Intent::FollowUp)
        end

        it "returns nil for '#{input}' when suggestions are available (ambiguous)" do
          result = router.send(:try_fast_classify, input, context_with_suggestions)

          expect(result).to be_nil
        end
      end

      it 'continues previous task in resolved_task' do
        result = router.send(:try_fast_classify, 'yes', context_without_suggestions)

        expect(result.resolved_task).to include('Write factorial function')
      end
    end

    describe 'no match cases' do
      [
        'Write a sorting function',
        'Can you also add logging?',
        'What about error handling?',
        'Make it recursive',
        'abc123'
      ].each do |input|
        it "returns nil for '#{input}' (requires LLM)" do
          result = router.send(:try_fast_classify, input, context_with_suggestions)

          expect(result).to be_nil
        end
      end
    end
  end

  describe '#classify' do
    context 'when fast-path matches' do
      it 'returns fast-path result without calling LLM' do
        # Ensure predictor is not called
        expect(router).not_to receive(:llm_classify)

        result = router.classify(input: '1', context: context_with_suggestions)

        expect(result.intent).to eq(Looped::Types::Intent::SelectSuggestion)
        expect(result.suggestion_index).to eq(1)
      end
    end
  end

  describe 'resolved task extraction' do
    it 'uses suggestion text as resolved_task for SelectSuggestion' do
      result = router.send(:try_fast_classify, '1', context_with_suggestions)

      expect(result.resolved_task).to eq('Add error handling for negative numbers')
    end

    it 'uses second suggestion for index 2' do
      result = router.send(:try_fast_classify, '2', context_with_suggestions)

      expect(result.resolved_task).to eq('Add memoization')
    end

    it 'uses third suggestion for index 3' do
      result = router.send(:try_fast_classify, '3', context_with_suggestions)

      expect(result.resolved_task).to eq('Add input validation')
    end
  end

  describe '#normalize_intent' do
    it 'passes through Intent enum directly' do
      expect(router.send(:normalize_intent, Looped::Types::Intent::NewTask)).to eq(Looped::Types::Intent::NewTask)
      expect(router.send(:normalize_intent, Looped::Types::Intent::FollowUp)).to eq(Looped::Types::Intent::FollowUp)
    end

    it 'parses new_task string' do
      expect(router.send(:normalize_intent, 'new_task')).to eq(Looped::Types::Intent::NewTask)
    end

    it 'parses follow_up string' do
      expect(router.send(:normalize_intent, 'follow_up')).to eq(Looped::Types::Intent::FollowUp)
    end

    it 'parses select_suggestion string' do
      expect(router.send(:normalize_intent, 'select_suggestion')).to eq(Looped::Types::Intent::SelectSuggestion)
    end

    it 'defaults to new_task for unknown values' do
      expect(router.send(:normalize_intent, 'unknown')).to eq(Looped::Types::Intent::NewTask)
      expect(router.send(:normalize_intent, '')).to eq(Looped::Types::Intent::NewTask)
    end

    it 'handles case variations' do
      expect(router.send(:normalize_intent, 'NEW_TASK')).to eq(Looped::Types::Intent::NewTask)
      expect(router.send(:normalize_intent, 'Follow_Up')).to eq(Looped::Types::Intent::FollowUp)
    end
  end
end
