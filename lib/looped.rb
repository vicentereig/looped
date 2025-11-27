# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'dspy'

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
  sig { params(options: T::Hash[Symbol, T.untyped]).void }
  def self.run(**options)
    app = Application.new(**options)
    app.run
  end

  # Run a single task without the interactive loop
  sig { params(task: String, context: String, options: T::Hash[Symbol, T.untyped]).returns(Types::TrainingResult) }
  def self.execute(task:, context: '', **options)
    app = Application.new(**options)
    app.run_task(task: task, context: context)
  end
end
