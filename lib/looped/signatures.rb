# typed: strict
# frozen_string_literal: true

require 'dspy'

module Looped
  # Main coding task signature
  class CodingTaskSignature < DSPy::Signature
    description "Complete a coding task in any programming language."

    input do
      const :task, String
      const :context, String, default: ''
      const :history, T::Array[Types::ActionSummary], default: []
    end

    output do
      const :solution, String
      const :files_modified, T::Array[String], default: []
    end
  end

  # LLM-as-Judge signature
  class JudgeSignature < DSPy::Signature
    description "Evaluate code quality and correctness. Be critical and thorough."

    input do
      const :task, String
      const :solution, String
      const :expected_behavior, String
    end

    output do
      const :score, Float
      const :passed, T::Boolean
      const :critique, String
      const :suggestions, T::Array[String]
    end
  end
end
