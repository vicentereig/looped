# typed: strict
# frozen_string_literal: true

module Looped
  class Memory
    extend T::Sig

    DEFAULT_MAX_ENTRIES = 10
    DEFAULT_MAX_RESULT_LENGTH = 500

    sig { params(max_entries: Integer, max_result_length: Integer).void }
    def initialize(max_entries: DEFAULT_MAX_ENTRIES, max_result_length: DEFAULT_MAX_RESULT_LENGTH)
      @entries = T.let([], T::Array[Types::MemoryEntry])
      @max_entries = max_entries
      @max_result_length = max_result_length
    end

    sig do
      params(
        action_type: String,
        action_input: T::Hash[T.any(String, Symbol), T.untyped],
        action_output: String,
        model_id: T.nilable(String),
        tokens_used: T.nilable(Integer),
        error: T.nilable(String)
      ).void
    end
    def add(action_type:, action_input:, action_output:, model_id: nil, tokens_used: nil, error: nil)
      @entries << Types::MemoryEntry.new(
        action_type: action_type,
        action_input: stringify_keys(action_input),
        action_output: action_output,
        timestamp: Time.now.utc.iso8601,
        model_id: model_id,
        error: error,
        tokens_used: tokens_used
      )

      # Enforce max_entries limit
      @entries.shift while @entries.size > @max_entries
    end

    sig { returns(T::Array[Types::ActionSummary]) }
    def to_context
      @entries.last(@max_entries).map do |entry|
        Types::ActionSummary.new(
          action: summarize_action(entry),
          result: truncate(entry.action_output)
        )
      end
    end

    sig { returns(T::Array[Types::MemoryEntry]) }
    def entries
      @entries.dup
    end

    sig { returns(Integer) }
    def size
      @entries.size
    end

    sig { void }
    def clear
      @entries.clear
    end

    sig { params(n: Integer).returns(T::Array[Types::MemoryEntry]) }
    def recent(n)
      @entries.last(n)
    end

    private

    sig { params(hash: T::Hash[T.any(String, Symbol), T.untyped]).returns(T::Hash[String, T.untyped]) }
    def stringify_keys(hash)
      hash.transform_keys(&:to_s)
    end

    sig { params(entry: Types::MemoryEntry).returns(String) }
    def summarize_action(entry)
      input_parts = entry.action_input.map do |k, v|
        value_str = v.to_s
        value_str = "#{value_str[0..47]}..." if value_str.length > 50
        "#{k}=#{value_str}"
      end
      "#{entry.action_type}(#{input_parts.join(', ')})"
    end

    sig { params(text: String).returns(String) }
    def truncate(text)
      return text if text.length <= @max_result_length
      "#{text[0...@max_result_length]}..."
    end
  end
end
