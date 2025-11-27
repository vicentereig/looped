# typed: strict
# frozen_string_literal: true

module Looped
  class Judge
    extend T::Sig

    DEFAULT_MODEL = 'gpt-4o-mini'

    sig { returns(DSPy::Predict) }
    attr_reader :predictor

    sig { params(model: T.nilable(String)).void }
    def initialize(model: nil)
      model_id = model || ENV.fetch('LOOPED_JUDGE_MODEL', DEFAULT_MODEL)
      lm = DSPy::LM.new(model_id)
      @predictor = T.let(DSPy::Predict.new(Signatures::JudgeSignature, lm: lm), DSPy::Predict)
    end

    sig { params(task: String, solution: String, expected_behavior: String).returns(Types::Judgment) }
    def evaluate(task:, solution:, expected_behavior: '')
      result = predictor.call(
        task: task,
        solution: solution,
        expected_behavior: expected_behavior.empty? ? infer_expected_behavior(task) : expected_behavior
      )

      Types::Judgment.new(
        score: normalize_score(result.score),
        passed: result.passed,
        critique: result.critique,
        suggestions: result.suggestions || []
      )
    end

    sig { params(judgment: Types::Judgment).returns(String) }
    def to_feedback(judgment)
      parts = []
      parts << "Score: #{judgment.score}/10"
      parts << "Status: #{judgment.passed ? 'PASSED' : 'FAILED'}"
      parts << ""
      parts << "Critique:"
      parts << judgment.critique

      if judgment.suggestions.any?
        parts << ""
        parts << "Suggestions for improvement:"
        judgment.suggestions.each_with_index do |suggestion, i|
          parts << "  #{i + 1}. #{suggestion}"
        end
      end

      parts.join("\n")
    end

    private

    sig { params(task: String).returns(String) }
    def infer_expected_behavior(task)
      "The solution should correctly and completely address the task: #{task}"
    end

    sig { params(score: T.untyped).returns(Float) }
    def normalize_score(score)
      value = score.to_f
      [[value, 0.0].max, 10.0].min
    end
  end
end
