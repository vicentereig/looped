# typed: strict
# frozen_string_literal: true

module Looped
  class IntentRouter
    extend T::Sig

    sig { params(model: T.nilable(String)).void }
    def initialize(model: nil)
      @model_id = T.let(model || ENV.fetch('LOOPED_MODEL', Agent::DEFAULT_MODEL), String)
      @predictor = T.let(nil, T.nilable(DSPy::Predict))
    end

    sig { params(input: String, context: Types::ConversationContext).returns(Types::IntentClassification) }
    def classify(input:, context:)
      # Fast-path: Check for direct suggestion selection patterns
      fast_result = try_fast_classify(input, context)
      return fast_result if fast_result

      # Use LLM for complex classification
      llm_classify(input, context)
    end

    private

    sig { returns(DSPy::Predict) }
    def predictor
      @predictor ||= begin
        DSPy.configure do |c|
          c.lm = DSPy::LM.new(@model_id, api_key: resolve_api_key(@model_id))
        end
        DSPy::Predict.new(IntentClassificationSignature)
      end
    end

    # Fast pattern matching for common cases (avoids LLM call)
    sig { params(input: String, context: Types::ConversationContext).returns(T.nilable(Types::IntentClassification)) }
    def try_fast_classify(input, context)
      normalized = input.strip.downcase

      # Pattern: "1", "2", "3", etc. - direct number selection
      if match = normalized.match(/^(\d+)$/)
        return try_suggestion_selection(match[1].to_i, context)
      end

      # Pattern: "go with 1", "go for 1", "option 1", "suggestion 1", "yeah 1", "do 1", "pick 1", "choose 1", "select 1"
      if match = normalized.match(/(?:go\s+(?:with|for)|option|suggestion|yes|yeah|do|pick|choose|select)\s*(\d+)\s*$/i)
        return try_suggestion_selection(T.must(match[1]).to_i, context)
      end

      # Pattern: "the first one", "the second one", "first suggestion", etc.
      ordinal_map = { 'first' => 1, 'second' => 2, 'third' => 3, 'fourth' => 4, 'fifth' => 5 }
      if match = normalized.match(/(?:the\s+)?(first|second|third|fourth|fifth)(?:\s+(?:one|suggestion|option))?$/i)
        index = ordinal_map[T.must(match[1]).downcase]
        return try_suggestion_selection(index, context) if index
      end

      # Pattern: "yes", "yeah", "sure", "ok", etc. without a number
      if normalized.match?(/^(?:yes|yeah|sure|ok|okay|yep|yup|do it|go ahead|proceed|continue)$/)
        # If there are suggestions available, this is ambiguous - fall back to LLM
        return nil if context.available_suggestions.any?

        # No suggestions, treat as follow-up to continue previous task
        if context.previous_task
          return Types::IntentClassification.new(
            intent: Types::Intent::FollowUp,
            resolved_task: "Continue with: #{context.previous_task}",
            suggestion_index: nil,
            confidence: 0.8,
            reasoning: 'Affirmative response to continue previous task'
          )
        end
      end

      # No fast-path match
      nil
    end

    sig { params(index: Integer, context: Types::ConversationContext).returns(T.nilable(Types::IntentClassification)) }
    def try_suggestion_selection(index, context)
      return nil if index < 1 || index > context.available_suggestions.length

      suggestion = context.available_suggestions[index - 1]
      return nil unless suggestion

      Types::IntentClassification.new(
        intent: Types::Intent::SelectSuggestion,
        resolved_task: suggestion,
        suggestion_index: index,
        confidence: 0.95,
        reasoning: "Matched suggestion selection pattern for suggestion ##{index}"
      )
    end

    sig { params(input: String, context: Types::ConversationContext).returns(Types::IntentClassification) }
    def llm_classify(input, context)
      result = predictor.call(
        user_input: input,
        previous_task: context.previous_task,
        previous_solution_summary: context.previous_solution_summary,
        available_suggestions: context.available_suggestions
      )

      Types::IntentClassification.new(
        intent: parse_intent(result.intent),
        resolved_task: result.resolved_task || input,
        suggestion_index: result.suggestion_index,
        confidence: (result.confidence || 0.5).to_f,
        reasoning: result.reasoning || 'LLM classification'
      )
    end

    sig { params(intent_str: String).returns(Types::Intent) }
    def parse_intent(intent_str)
      case intent_str.to_s.downcase.strip
      when 'new_task' then Types::Intent::NewTask
      when 'follow_up' then Types::Intent::FollowUp
      when 'select_suggestion' then Types::Intent::SelectSuggestion
      else Types::Intent::NewTask
      end
    end

    sig { params(model_id: String).returns(T.nilable(String)) }
    def resolve_api_key(model_id)
      provider = model_id.split('/').first
      case provider
      when 'openai' then ENV['OPENAI_API_KEY']
      when 'anthropic' then ENV['ANTHROPIC_API_KEY']
      when 'gemini', 'google' then ENV['GEMINI_API_KEY']
      else ENV['OPENAI_API_KEY']
      end
    end
  end
end
