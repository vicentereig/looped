# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'dspy'
require 'dspy/openai'

# Load GEPA extension
begin
  require 'dspy/teleprompt/gepa'
rescue LoadError
  # GEPA not available - optimization will be limited
end

require_relative 'looped/version'
require_relative 'looped/types'
require_relative 'looped/signatures'
require_relative 'looped/memory'
require_relative 'looped/state'

# Tools
require_relative 'looped/tools/read_file'
require_relative 'looped/tools/write_file'
require_relative 'looped/tools/search_code'
require_relative 'looped/tools/run_command'

require_relative 'looped/judge'
require_relative 'looped/agent'
require_relative 'looped/optimizer'
require_relative 'looped/application'

module Looped
  extend T::Sig

  class Error < StandardError; end

  # Convenience method to create and run the application
  sig do
    params(
      model: T.nilable(String),
      judge_model: T.nilable(String),
      reflection_model: T.nilable(String),
      max_iterations: Integer,
      optimizer_batch_size: Integer,
      optimizer_interval: Integer
    ).void
  end
  def self.run(
    model: nil,
    judge_model: nil,
    reflection_model: nil,
    max_iterations: 10,
    optimizer_batch_size: 5,
    optimizer_interval: 60
  )
    app = Application.new(
      model: model,
      judge_model: judge_model,
      reflection_model: reflection_model,
      max_iterations: max_iterations,
      optimizer_batch_size: optimizer_batch_size,
      optimizer_interval: optimizer_interval
    )
    app.run
  end

  # Run a single task without the interactive loop
  sig do
    params(
      task: String,
      context: String,
      model: T.nilable(String),
      judge_model: T.nilable(String),
      reflection_model: T.nilable(String),
      max_iterations: Integer,
      optimizer_batch_size: Integer,
      optimizer_interval: Integer
    ).returns(Types::TrainingResult)
  end
  def self.execute(
    task:,
    context: '',
    model: nil,
    judge_model: nil,
    reflection_model: nil,
    max_iterations: 10,
    optimizer_batch_size: 5,
    optimizer_interval: 60
  )
    app = Application.new(
      model: model,
      judge_model: judge_model,
      reflection_model: reflection_model,
      max_iterations: max_iterations,
      optimizer_batch_size: optimizer_batch_size,
      optimizer_interval: optimizer_interval
    )
    app.run_task(task: task, context: context)
  end
end
