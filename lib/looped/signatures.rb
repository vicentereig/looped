# typed: strict
# frozen_string_literal: true

require 'dspy'

module Looped
  # Main coding task signature
  class CodingTaskSignature < DSPy::Signature
    description "Complete a coding task in any programming language."

    input do
      const :task, String, description: 'The coding task to complete'
      const :context, String, default: '', description: 'Additional context or constraints'
      const :history, T::Array[Types::ActionSummary], default: [], description: 'Previous actions taken'
    end

    output do
      const :solution, String, description: 'Explanation of the solution and approach taken'
      const :files_modified, T::Array[String], default: [], description: 'List of files created or modified'
    end
  end

  # LLM-as-Judge signature
  class JudgeSignature < DSPy::Signature
    description "Evaluate code quality and correctness. Be critical and thorough."

    input do
      const :task, String, description: 'The original task that was attempted'
      const :solution, String, description: 'The solution to evaluate'
      const :expected_behavior, String, description: 'What the solution should accomplish'
    end

    output do
      const :score, Float, description: 'Quality score from 0.0 to 10.0'
      const :passed, T::Boolean, description: 'Whether the solution meets requirements'
      const :critique, String, description: 'Detailed analysis of strengths and weaknesses'
      const :suggestions, T::Array[String], description: 'Specific improvements to make'
    end
  end

  # Intent classification for routing user input
  class IntentClassificationSignature < DSPy::Signature
    description 'Classify user input and resolve it to an executable task.'

    input do
      const :user_input, String, description: 'Raw input from the user'
      const :previous_task, T.nilable(String), default: nil, description: 'The last task that was executed'
      const :previous_solution_summary, T.nilable(String), default: nil, description: 'Summary of the previous solution'
      const :available_suggestions, T::Array[String], default: [], description: 'Numbered suggestions from previous response'
    end

    output do
      const :intent, Types::Intent, description: 'Classification: new_task, follow_up, or select_suggestion'
      const :resolved_task, String, description: 'The executable task (use suggestion text if selecting)'
      const :suggestion_index, T.nilable(Integer), description: '1-based index if selecting a suggestion'
      const :confidence, Float, description: 'Confidence score from 0.0 to 1.0'
      const :reasoning, String, description: 'Brief explanation of the classification'
    end
  end
end
