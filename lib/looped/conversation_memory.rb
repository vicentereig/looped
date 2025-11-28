# typed: strict
# frozen_string_literal: true

require 'json'
require 'fileutils'

module Looped
  class ConversationMemory
    extend T::Sig

    DEFAULT_STORAGE_DIR = T.let(File.expand_path('~/.looped'), String)
    DEFAULT_MAX_TURNS = 10

    sig { returns(T::Array[Types::ConversationTurn]) }
    attr_reader :turns

    sig { returns(String) }
    attr_reader :storage_dir

    sig { params(storage_dir: T.nilable(String), max_turns: Integer).void }
    def initialize(storage_dir: nil, max_turns: DEFAULT_MAX_TURNS)
      @storage_dir = T.let(
        storage_dir || ENV['LOOPED_STORAGE_DIR'] || DEFAULT_STORAGE_DIR,
        String
      )
      @max_turns = max_turns
      @turns = T.let([], T::Array[Types::ConversationTurn])
      @current_suggestions = T.let([], T::Array[String])

      FileUtils.mkdir_p(@storage_dir)
      load
    end

    sig do
      params(
        task: String,
        resolved_task: String,
        solution: String,
        score: Float,
        suggestions: T::Array[String],
        judgment: T.nilable(Types::Judgment)
      ).void
    end
    def add_turn(task:, resolved_task:, solution:, score:, suggestions: [], judgment: nil)
      turn = Types::ConversationTurn.new(
        task: task,
        resolved_task: resolved_task,
        solution: solution,
        score: score,
        suggestions: suggestions,
        judgment: judgment,
        timestamp: Time.now.utc.iso8601,
        turn_number: @turns.length + 1
      )

      @turns << turn
      @current_suggestions = suggestions

      # Enforce max turns
      @turns.shift while @turns.length > @max_turns

      save
    end

    sig { returns(Types::ConversationContext) }
    def to_context
      last_turn = @turns.last

      Types::ConversationContext.new(
        previous_task: last_turn&.resolved_task,
        previous_solution_summary: summarize_solution(last_turn&.solution),
        available_suggestions: @current_suggestions
      )
    end

    sig { params(index: Integer).returns(T.nilable(String)) }
    def suggestion_at(index)
      return nil if index < 1 || index > @current_suggestions.length

      @current_suggestions[index - 1]
    end

    sig { returns(T::Array[String]) }
    def current_suggestions
      @current_suggestions.dup
    end

    sig { returns(T.nilable(Types::ConversationTurn)) }
    def last_turn
      @turns.last
    end

    sig { void }
    def clear
      @turns.clear
      @current_suggestions.clear

      # Remove the conversation file
      File.delete(conversation_path) if File.exist?(conversation_path)
    end

    sig { returns(Integer) }
    def turn_count
      @turns.length
    end

    private

    sig { returns(String) }
    def conversation_path
      File.join(@storage_dir, 'conversation.json')
    end

    sig { void }
    def save
      data = {
        turns: @turns.map { |turn| serialize_turn(turn) },
        current_suggestions: @current_suggestions,
        updated_at: Time.now.utc.iso8601
      }
      File.write(conversation_path, JSON.pretty_generate(data))
    end

    sig { void }
    def load
      return unless File.exist?(conversation_path)

      data = JSON.parse(File.read(conversation_path), symbolize_names: true)

      @turns = (data[:turns] || []).map { |turn_data| deserialize_turn(turn_data) }
      @current_suggestions = data[:current_suggestions] || []

      # Enforce max turns on load
      @turns.shift while @turns.length > @max_turns
    rescue JSON::ParserError
      # Start fresh if file is corrupted
      @turns = []
      @current_suggestions = []
    end

    sig { params(turn: Types::ConversationTurn).returns(T::Hash[Symbol, T.untyped]) }
    def serialize_turn(turn)
      {
        task: turn.task,
        resolved_task: turn.resolved_task,
        solution: turn.solution,
        score: turn.score,
        suggestions: turn.suggestions,
        judgment: turn.judgment ? serialize_judgment(turn.judgment) : nil,
        timestamp: turn.timestamp,
        turn_number: turn.turn_number
      }
    end

    sig { params(judgment: Types::Judgment).returns(T::Hash[Symbol, T.untyped]) }
    def serialize_judgment(judgment)
      {
        score: judgment.score,
        passed: judgment.passed,
        critique: judgment.critique,
        suggestions: judgment.suggestions
      }
    end

    sig { params(data: T::Hash[Symbol, T.untyped]).returns(Types::ConversationTurn) }
    def deserialize_turn(data)
      judgment = data[:judgment] ? deserialize_judgment(data[:judgment]) : nil

      Types::ConversationTurn.new(
        task: data[:task] || '',
        resolved_task: data[:resolved_task] || '',
        solution: data[:solution] || '',
        score: data[:score]&.to_f || 0.0,
        suggestions: data[:suggestions] || [],
        judgment: judgment,
        timestamp: data[:timestamp] || Time.now.utc.iso8601,
        turn_number: data[:turn_number]&.to_i || 1
      )
    end

    sig { params(data: T::Hash[Symbol, T.untyped]).returns(Types::Judgment) }
    def deserialize_judgment(data)
      Types::Judgment.new(
        score: data[:score]&.to_f || 0.0,
        passed: data[:passed] || false,
        critique: data[:critique] || '',
        suggestions: data[:suggestions] || []
      )
    end

    sig { params(solution: T.nilable(String)).returns(T.nilable(String)) }
    def summarize_solution(solution)
      return nil unless solution
      return solution if solution.length <= 200

      "#{solution[0..197]}..."
    end
  end
end
