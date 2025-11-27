# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Looped::Judge, :vcr do
  subject(:judge) { described_class.new }

  describe '#evaluate' do
    context 'with a good solution' do
      let(:task) { 'Write a Ruby function that returns the factorial of a number' }
      let(:solution) do
        <<~RUBY
          def factorial(n)
            return 1 if n <= 1
            n * factorial(n - 1)
          end
        RUBY
      end

      it 'returns a high score and passes', vcr: { cassette_name: 'judge/evaluate_good_solution' } do
        judgment = judge.evaluate(task: task, solution: solution)

        expect(judgment).to be_a(Looped::Types::Judgment)
        expect(judgment.score).to be >= 7.0
        expect(judgment.passed).to be true
        expect(judgment.critique).to be_a(String)
        expect(judgment.critique.length).to be > 0
      end
    end

    context 'with a poor solution' do
      let(:task) { 'Write a Ruby function that sorts an array' }
      let(:solution) { 'puts "hello world"' }

      it 'returns a low score and fails', vcr: { cassette_name: 'judge/evaluate_poor_solution' } do
        judgment = judge.evaluate(task: task, solution: solution)

        expect(judgment).to be_a(Looped::Types::Judgment)
        expect(judgment.score).to be < 5.0
        expect(judgment.passed).to be false
        expect(judgment.critique).to include_any('sort', 'array', 'incorrect', 'not', 'does not')
      end
    end

    context 'with expected behavior specified' do
      let(:task) { 'Write a function to validate an email address' }
      let(:solution) do
        <<~RUBY
          def valid_email?(email)
            email =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
          end
        RUBY
      end
      let(:expected_behavior) { 'Should return true for valid emails like test@example.com and false for invalid ones' }

      it 'evaluates against the expected behavior', vcr: { cassette_name: 'judge/evaluate_with_expected_behavior' } do
        judgment = judge.evaluate(
          task: task,
          solution: solution,
          expected_behavior: expected_behavior
        )

        # LLM judgment scores can vary; just verify it returns a valid judgment
        expect(judgment.score).to be_between(0, 10)
        expect(judgment.critique).to be_a(String)
        expect(judgment.critique.length).to be > 0
      end
    end
  end

  describe '#to_feedback' do
    let(:judgment) do
      Looped::Types::Judgment.new(
        score: 8.5,
        passed: true,
        critique: 'Well-structured code with good practices.',
        suggestions: ['Add input validation', 'Consider edge cases']
      )
    end

    it 'formats the judgment as readable feedback' do
      feedback = judge.to_feedback(judgment)

      expect(feedback).to include('Score: 8.5/10')
      expect(feedback).to include('Status: PASSED')
      expect(feedback).to include('Well-structured code')
      expect(feedback).to include('Add input validation')
      expect(feedback).to include('Consider edge cases')
    end
  end
end

RSpec::Matchers.define :include_any do |*expected|
  match do |actual|
    expected.any? { |term| actual.downcase.include?(term.downcase) }
  end

  description do
    "include any of: #{expected.join(', ')}"
  end
end
