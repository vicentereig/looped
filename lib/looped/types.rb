# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module Looped
  module Types
    extend T::Sig

    # Rich memory entry for storage/analytics
    class MemoryEntry < T::Struct
      const :action_type, String
      const :action_input, T::Hash[String, T.untyped]
      const :action_output, String
      const :timestamp, String
      const :model_id, T.nilable(String)
      const :error, T.nilable(String)
      const :tokens_used, T.nilable(Integer)
    end

    # Lean context entry for prompts
    class ActionSummary < T::Struct
      const :action, String
      const :result, String
    end

    # Training result stored to buffer
    class TrainingResult < T::Struct
      const :task, String
      const :solution, String
      const :score, Float
      const :feedback, String
      const :timestamp, String
    end

    # Persisted instructions with metadata
    class Instructions < T::Struct
      const :thought_generator, T.nilable(String)
      const :observation_processor, T.nilable(String)
      const :score, Float, default: 0.0
      const :generation, Integer, default: 0
      const :updated_at, String
    end

    # Judgment from LLM-as-judge
    class Judgment < T::Struct
      const :score, Float
      const :passed, T::Boolean
      const :critique, String
      const :suggestions, T::Array[String], default: []
    end

    # Intent classification for user input routing
    class Intent < T::Enum
      enums do
        NewTask = new('new_task')
        FollowUp = new('follow_up')
        SelectSuggestion = new('select_suggestion')
      end
    end

    # Rich conversation turn for storage/persistence
    class ConversationTurn < T::Struct
      const :task, String                              # Original user input
      const :resolved_task, String                     # Task after intent resolution
      const :solution, String
      const :score, Float
      const :suggestions, T::Array[String], default: []
      const :judgment, T.nilable(Judgment)
      const :timestamp, String
      const :turn_number, Integer
    end

    # Lean context for LLM prompts
    class ConversationContext < T::Struct
      const :previous_task, T.nilable(String)
      const :previous_solution_summary, T.nilable(String)
      const :available_suggestions, T::Array[String], default: []
    end

    # Result of intent classification
    class IntentClassification < T::Struct
      const :intent, Intent
      const :resolved_task, String
      const :suggestion_index, T.nilable(Integer)
      const :confidence, Float
      const :reasoning, String
    end
  end
end
