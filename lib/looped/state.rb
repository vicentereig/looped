# typed: strict
# frozen_string_literal: true

require 'json'
require 'fileutils'

module Looped
  class State
    extend T::Sig

    STORAGE_DIR = T.let(File.expand_path('~/.looped'), String)

    sig { void }
    def initialize
      FileUtils.mkdir_p(STORAGE_DIR)
      FileUtils.mkdir_p(File.join(STORAGE_DIR, 'history'))
    end

    sig { returns(T.nilable(Types::Instructions)) }
    def load_instructions
      path = instructions_path
      return nil unless File.exist?(path)

      data = JSON.parse(File.read(path), symbolize_names: true)
      instructions_data = data[:instructions] || {}

      Types::Instructions.new(
        thought_generator: instructions_data[:thought_generator],
        observation_processor: instructions_data[:observation_processor],
        score: data[:score]&.to_f || 0.0,
        generation: data[:generation]&.to_i || 0,
        updated_at: data[:updated_at] || Time.now.utc.iso8601
      )
    rescue JSON::ParserError
      nil
    end

    sig { params(instructions: T::Hash[Symbol, T.nilable(String)], score: Float, generation: Integer).void }
    def save_instructions(instructions:, score:, generation:)
      data = {
        instructions: instructions,
        score: score,
        generation: generation,
        updated_at: Time.now.utc.iso8601
      }
      File.write(instructions_path, JSON.pretty_generate(data))
    end

    sig { params(result: Types::TrainingResult).void }
    def append_training_result(result)
      buffer = load_training_buffer_raw
      buffer << {
        task: result.task,
        solution: result.solution,
        score: result.score,
        feedback: result.feedback,
        timestamp: result.timestamp
      }
      File.write(training_buffer_path, JSON.pretty_generate(buffer))
    end

    sig { returns(T::Array[Types::TrainingResult]) }
    def peek_training_buffer
      load_training_buffer_raw.map { |data| deserialize_training_result(data) }
    end

    sig { returns(T::Array[Types::TrainingResult]) }
    def consume_training_buffer
      buffer = peek_training_buffer
      return [] if buffer.empty?

      # Archive to history
      archive_path = File.join(STORAGE_DIR, 'history', "#{Time.now.to_i}.json")
      File.write(archive_path, JSON.pretty_generate(load_training_buffer_raw))

      # Clear buffer
      File.write(training_buffer_path, '[]')

      buffer
    end

    sig { returns(String) }
    def storage_dir
      STORAGE_DIR
    end

    private

    sig { returns(String) }
    def instructions_path
      File.join(STORAGE_DIR, 'instructions.json')
    end

    sig { returns(String) }
    def training_buffer_path
      File.join(STORAGE_DIR, 'training_buffer.json')
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def load_training_buffer_raw
      return [] unless File.exist?(training_buffer_path)
      JSON.parse(File.read(training_buffer_path), symbolize_names: true)
    rescue JSON::ParserError
      []
    end

    sig { params(data: T::Hash[Symbol, T.untyped]).returns(Types::TrainingResult) }
    def deserialize_training_result(data)
      Types::TrainingResult.new(
        task: data[:task] || '',
        solution: data[:solution] || '',
        score: data[:score]&.to_f || 0.0,
        feedback: data[:feedback] || '',
        timestamp: data[:timestamp] || Time.now.utc.iso8601
      )
    end
  end
end
