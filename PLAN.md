# Looped - Self-Improving Coding Agent

## Overview

**looped** is a standalone Ruby gem that provides a **self-improving coding agent**:
1. Uses **DSPy.rb ReAct** with coding tools for controlled, auditable actions
2. Implements **ephemeral memory** with context engineering (rich storage, lean prompts)
3. **Continuously evolves prompts** using GEPA running as a background async task
4. Evaluates with **LLM-as-judge** (configurable model)
5. **Persists state to disk** (~/.looped/) for cross-session learning
6. **Full Sorbet type annotations** throughout

**Dependency**: `dspy-rb` gem (including `dspy-gepa`)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Foreground                               │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                   Looped::Agent                           │ │
│  │  - Loads current best instructions from disk              │ │
│  │  - Handles coding tasks with DSPy::ReAct + tools          │ │
│  │  - Writes results to training buffer                      │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ writes
┌─────────────────────────────────────────────────────────────────┐
│                         ~/.looped/                              │
│  ├── instructions.json      # Current best instructions         │
│  ├── frontier.json          # Pareto frontier state             │
│  ├── training_buffer.json   # Recent task results for learning  │
│  └── history/               # Historical training data          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▲ reads/updates
┌─────────────────────────────────────────────────────────────────┐
│                     Background (Async Task)                     │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                  Looped::Optimizer                        │ │
│  │  - Monitors training buffer for new results               │ │
│  │  - Runs GEPA reflection cycles when buffer has data       │ │
│  │  - Evaluates candidates against validation set            │ │
│  │  - Hot-swaps instructions.json when improvement found     │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Gem Structure

```
looped/
├── looped.gemspec
├── Gemfile
├── README.md
├── LICENSE.txt
├── bin/
│   └── looped                    # CLI entry point
├── lib/
│   ├── looped.rb                 # Main entry, Looped.start
│   └── looped/
│       ├── version.rb
│       ├── types.rb              # Sorbet T::Struct types
│       ├── signatures.rb         # DSPy Signatures
│       ├── agent.rb              # Looped::Agent (ReAct-based)
│       ├── optimizer.rb          # Looped::Optimizer (GEPA wrapper)
│       ├── state.rb              # Looped::State (file persistence)
│       ├── judge.rb              # Looped::Judge (LLM-as-judge)
│       ├── memory.rb             # Looped::Memory (context engineering)
│       └── tools/
│           ├── base.rb           # Common tool functionality
│           ├── read_file.rb
│           ├── write_file.rb
│           ├── run_command.rb    # Docker-sandboxed
│           └── search_code.rb
└── spec/
    ├── spec_helper.rb
    ├── looped/
    │   ├── agent_spec.rb
    │   ├── optimizer_spec.rb
    │   ├── state_spec.rb
    │   └── memory_spec.rb
    └── integration/
        └── full_loop_spec.rb     # VCR-recorded integration test
```

## Implementation Plan

### Step 1: Sorbet Types (lib/looped/types.rb)

```ruby
# typed: strict
# frozen_string_literal: true

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
      const :score, Float
      const :generation, Integer
      const :updated_at, String
    end

    # Judgment from LLM-as-judge
    class Judgment < T::Struct
      const :score, Float
      const :passed, T::Boolean
      const :critique, String
      const :suggestions, T::Array[String]
    end
  end
end
```

### Step 2: DSPy Signatures (lib/looped/signatures.rb)

```ruby
# typed: strict
# frozen_string_literal: true

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
      const :files_modified, T::Array[String]
    end
  end

  # LLM-as-Judge signature
  class JudgeSignature < DSPy::Signature
    description "Evaluate code quality and correctness."

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
```

### Step 3: Memory with Context Engineering (lib/looped/memory.rb)

```ruby
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

    sig { params(action: String, input: T::Hash[String, T.untyped], output: String, model_id: T.nilable(String)).void }
    def add(action:, input:, output:, model_id: nil)
      @entries << Types::MemoryEntry.new(
        action_type: action,
        action_input: input,
        action_output: output,
        timestamp: Time.now.utc.iso8601,
        model_id: model_id,
        error: nil,
        tokens_used: nil
      )
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

    sig { void }
    def clear
      @entries.clear
    end

    private

    sig { params(entry: Types::MemoryEntry).returns(String) }
    def summarize_action(entry)
      input_summary = entry.action_input.map { |k, v| "#{k}=#{v.to_s[0..50]}" }.join(', ')
      "#{entry.action_type}(#{input_summary})"
    end

    sig { params(text: String).returns(String) }
    def truncate(text)
      return text if text.length <= @max_result_length
      "#{text[0...@max_result_length]}..."
    end
  end
end
```

### Step 4: State Persistence (lib/looped/state.rb)

```ruby
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
      Types::Instructions.new(
        thought_generator: data.dig(:instructions, :thought_generator),
        observation_processor: data.dig(:instructions, :observation_processor),
        score: data[:score] || 0.0,
        generation: data[:generation] || 0,
        updated_at: data[:updated_at] || Time.now.utc.iso8601
      )
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
      buffer = load_training_buffer
      buffer << result.serialize
      File.write(training_buffer_path, JSON.pretty_generate(buffer))
    end

    sig { returns(T::Array[Types::TrainingResult]) }
    def peek_training_buffer
      load_training_buffer.map { |data| deserialize_training_result(data) }
    end

    sig { returns(T::Array[Types::TrainingResult]) }
    def consume_training_buffer
      buffer = peek_training_buffer
      return [] if buffer.empty?

      # Archive to history
      archive_path = File.join(STORAGE_DIR, 'history', "#{Time.now.to_i}.json")
      File.write(archive_path, JSON.pretty_generate(load_training_buffer))

      # Clear buffer
      File.write(training_buffer_path, '[]')

      buffer
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
    def load_training_buffer
      return [] unless File.exist?(training_buffer_path)
      JSON.parse(File.read(training_buffer_path), symbolize_names: true)
    end

    sig { params(data: T::Hash[Symbol, T.untyped]).returns(Types::TrainingResult) }
    def deserialize_training_result(data)
      Types::TrainingResult.new(
        task: data[:task],
        solution: data[:solution],
        score: data[:score],
        feedback: data[:feedback],
        timestamp: data[:timestamp]
      )
    end
  end
end
```

### Step 5: Tools (lib/looped/tools/)

```ruby
# typed: strict
# frozen_string_literal: true

# lib/looped/tools/read_file.rb
module Looped
  module Tools
    class ReadFile < DSPy::Tools::Base
      extend T::Sig

      tool_name 'read_file'
      tool_description 'Read contents of a file at the given path'

      sig { params(path: String).returns(String) }
      def call(path:)
        File.read(path)
      rescue Errno::ENOENT
        "Error: File not found: #{path}"
      rescue Errno::EACCES
        "Error: Permission denied: #{path}"
      rescue => e
        "Error: #{e.message}"
      end
    end

    # lib/looped/tools/write_file.rb
    class WriteFile < DSPy::Tools::Base
      extend T::Sig

      tool_name 'write_file'
      tool_description 'Write content to a file at the given path'

      sig { params(path: String, content: String).returns(String) }
      def call(path:, content:)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
        "Successfully wrote #{content.length} bytes to #{path}"
      rescue => e
        "Error: #{e.message}"
      end
    end

    # lib/looped/tools/search_code.rb
    class SearchCode < DSPy::Tools::Base
      extend T::Sig

      tool_name 'search_code'
      tool_description 'Search for a pattern in code files using ripgrep'

      sig { params(pattern: String, path: String, file_type: T.nilable(String)).returns(String) }
      def call(pattern:, path: '.', file_type: nil)
        cmd = ['rg', '--line-number', '--no-heading', pattern, path]
        cmd += ['--type', file_type] if file_type

        output, status = Open3.capture2(*cmd)
        status.success? ? output : "No matches found for: #{pattern}"
      rescue => e
        "Error: #{e.message}"
      end
    end

    # lib/looped/tools/run_command.rb
    class RunCommand < DSPy::Tools::Base
      extend T::Sig

      DEFAULT_TIMEOUT = 30

      tool_name 'run_command'
      tool_description 'Execute a shell command in a Docker sandbox and return output'

      sig { params(command: String, timeout: Integer).returns(String) }
      def call(command:, timeout: DEFAULT_TIMEOUT)
        # TODO: Implement Docker sandbox via trusted-sandbox gem
        # For now, basic execution with timeout
        Timeout.timeout(timeout) do
          output, status = Open3.capture2e(command)
          "Exit code: #{status.exitstatus}\n#{output}"
        end
      rescue Timeout::Error
        "Error: Command timed out after #{timeout} seconds"
      rescue => e
        "Error: #{e.message}"
      end
    end
  end
end
```

### Step 6: Judge (lib/looped/judge.rb)

```ruby
# typed: strict
# frozen_string_literal: true

module Looped
  class Judge < DSPy::Predict
    extend T::Sig

    sig { void }
    def initialize
      super(JudgeSignature)
    end

    sig { params(task: String, solution: String, expected_behavior: String).returns(Types::Judgment) }
    def evaluate(task:, solution:, expected_behavior:)
      result = call(
        task: task,
        solution: solution,
        expected_behavior: expected_behavior
      )

      Types::Judgment.new(
        score: result.score,
        passed: result.passed,
        critique: result.critique,
        suggestions: result.suggestions
      )
    end
  end
end
```

### Step 7: Agent (lib/looped/agent.rb)

```ruby
# typed: strict
# frozen_string_literal: true

module Looped
  class Agent < DSPy::Module
    extend T::Sig

    around :update_memory
    around :record_for_training

    sig { params(tools: T::Array[DSPy::Tools::Base], state: State, max_context_entries: Integer).void }
    def initialize(tools:, state:, max_context_entries: 10)
      super()
      @state = state
      @memory = Memory.new(max_entries: max_context_entries)
      @react = T.let(
        DSPy::ReAct.new(CodingTaskSignature, tools: tools, max_iterations: 15),
        DSPy::ReAct
      )
      @judge = T.let(Judge.new, Judge)
      @current_task = T.let(nil, T.nilable(String))

      reload_instructions
    end

    sig { void }
    def reload_instructions
      instructions = @state.load_instructions
      return unless instructions

      apply_instructions(instructions)
      puts "[agent] Loaded instructions (gen #{instructions.generation}, score #{instructions.score.round(2)})"
    end

    sig { params(instructions: Types::Instructions).void }
    def apply_instructions(instructions)
      @react.with_instruction(instructions.thought_generator) if instructions.thought_generator
    end

    sig { returns(T::Hash[Symbol, T.nilable(String)]) }
    def extract_instructions
      {
        thought_generator: @react.named_predictors['thought_generator']&.instruction,
        observation_processor: @react.named_predictors['observation_processor']&.instruction
      }
    end

    sig { params(task: String, context: String).returns(T.untyped) }
    def forward(task:, context: '')
      @current_task = task
      history = @memory.to_context

      @react.forward(
        task: task,
        context: context,
        history: history
      )
    end

    private

    sig { params(_args: T.untyped, kwargs: T.untyped, block: T.proc.returns(T.untyped)).returns(T.untyped) }
    def update_memory(_args, kwargs, &block)
      result = yield

      result.history&.each do |step|
        @memory.add(
          action: step[:action],
          input: step[:action_input] || {},
          output: step[:observation] || ''
        )
      end

      result
    end

    sig { params(_args: T.untyped, kwargs: T.untyped, block: T.proc.returns(T.untyped)).returns(T.untyped) }
    def record_for_training(_args, kwargs, &block)
      result = yield
      task = @current_task

      return result unless task

      judgment = @judge.evaluate(
        task: task,
        solution: result.solution || '',
        expected_behavior: "Task completed successfully"
      )

      training_result = Types::TrainingResult.new(
        task: task,
        solution: result.solution || '',
        score: judgment.score,
        feedback: judgment.critique,
        timestamp: Time.now.utc.iso8601
      )

      @state.append_training_result(training_result)

      result
    end
  end
end
```

### Step 8: Optimizer (lib/looped/optimizer.rb)

```ruby
# typed: strict
# frozen_string_literal: true

module Looped
  class Optimizer
    extend T::Sig

    MIN_BUFFER_SIZE = 10
    POLL_INTERVAL = 60

    sig do
      params(
        state: State,
        agent_builder: T.proc.returns(Agent),
        judge_lm: DSPy::LM,
        on_improvement: T.nilable(T.proc.void)
      ).void
    end
    def initialize(state:, agent_builder:, judge_lm:, on_improvement: nil)
      @state = state
      @agent_builder = agent_builder
      @judge_lm = judge_lm
      @reflection_lm = T.let(DSPy::ReflectionLM.new('openai/gpt-4o-mini'), DSPy::ReflectionLM)
      @on_improvement = on_improvement
    end

    sig { void }
    def run_forever
      loop do
        begin
          check_and_optimize
        rescue => e
          puts "[optimizer] Error: #{e.message}"
        end

        sleep POLL_INTERVAL
      end
    end

    private

    sig { void }
    def check_and_optimize
      buffer = @state.peek_training_buffer
      return if buffer.size < MIN_BUFFER_SIZE

      puts "[optimizer] Found #{buffer.size} results. Running GEPA..."

      buffer = @state.consume_training_buffer

      trainset = buffer.map do |result|
        DSPy::Example.new(
          inputs: { task: result.task },
          expected: { expected_behavior: result.feedback }
        )
      end

      train, val = trainset.partition.with_index { |_, i| i % 5 != 0 }

      agent = @agent_builder.call
      current = @state.load_instructions

      if current
        agent.apply_instructions(current)
      end

      gepa = DSPy::Teleprompt::GEPA.new(
        metric: create_metric,
        reflection_lm: @reflection_lm,
        config: { max_metric_calls: 50, minibatch_size: 4 }
      )

      result = gepa.compile(agent, trainset: train, valset: val)
      current_score = current&.score || 0.0

      if result.best_score_value > current_score
        puts "[optimizer] Improvement! #{current_score.round(2)} → #{result.best_score_value.round(2)}"

        @state.save_instructions(
          instructions: result.optimized_program.extract_instructions,
          score: result.best_score_value,
          generation: (current&.generation || 0) + 1
        )

        @on_improvement&.call
      else
        puts "[optimizer] No improvement. Score: #{result.best_score_value.round(2)}"
      end
    end

    sig { returns(T.proc.params(example: DSPy::Example, prediction: T.untyped).returns(DSPy::Prediction)) }
    def create_metric
      judge = Judge.new
      judge.configure { |c| c.lm = @judge_lm }

      lambda do |example, prediction|
        judgment = judge.evaluate(
          task: example.input_values[:task],
          solution: prediction.solution || '',
          expected_behavior: example.expected_values[:expected_behavior]
        )

        DSPy::Prediction.new(score: judgment.score, feedback: judgment.critique)
      end
    end
  end
end
```

### Step 9: Main Entry Point (lib/looped.rb)

```ruby
# typed: strict
# frozen_string_literal: true

require 'async'
require 'dspy'
require 'dspy/gepa'

require_relative 'looped/version'
require_relative 'looped/types'
require_relative 'looped/signatures'
require_relative 'looped/memory'
require_relative 'looped/state'
require_relative 'looped/tools/read_file'
require_relative 'looped/tools/write_file'
require_relative 'looped/tools/search_code'
require_relative 'looped/tools/run_command'
require_relative 'looped/judge'
require_relative 'looped/agent'
require_relative 'looped/optimizer'

module Looped
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(judge_model: T.nilable(String), agent_model: T.nilable(String)).void }
    def start(judge_model: nil, agent_model: nil)
      app = Application.new(judge_model: judge_model, agent_model: agent_model)
      app.run
    end
  end

  class Application
    extend T::Sig

    sig { params(judge_model: T.nilable(String), agent_model: T.nilable(String)).void }
    def initialize(judge_model: nil, agent_model: nil)
      @state = T.let(State.new, State)
      @judge_lm = T.let(
        DSPy::LM.new(judge_model || ENV['LOOPED_JUDGE_MODEL'] || 'openai/gpt-4o'),
        DSPy::LM
      )
      @agent_lm = T.let(
        DSPy::LM.new(agent_model || ENV['LOOPED_AGENT_MODEL'] || 'openai/gpt-4o-mini'),
        DSPy::LM
      )

      @agent = T.let(build_agent, Agent)
      @optimizer = T.let(
        Optimizer.new(
          state: @state,
          agent_builder: -> { build_agent },
          judge_lm: @judge_lm,
          on_improvement: -> { @agent.reload_instructions }
        ),
        Optimizer
      )
    end

    sig { void }
    def run
      Async do |task|
        optimizer_task = task.async { @optimizer.run_forever }

        puts "[looped] Optimizer started (background)"
        puts "[looped] Agent ready. Type a task or 'quit' to exit."

        loop do
          print "\n> "
          input = $stdin.gets&.chomp
          break if input.nil? || input == 'quit'
          next if input.empty?

          begin
            result = @agent.forward(task: input)
            puts "\n#{result.solution}"
          rescue => e
            puts "[error] #{e.message}"
          end
        end

        optimizer_task.stop
        puts "\n[looped] Goodbye! State saved to ~/.looped/"
      end
    end

    private

    sig { returns(Agent) }
    def build_agent
      tools = T.let([
        Tools::ReadFile.new,
        Tools::WriteFile.new,
        Tools::RunCommand.new,
        Tools::SearchCode.new
      ], T::Array[DSPy::Tools::Base])

      agent = Agent.new(tools: tools, state: @state)
      agent.configure { |c| c.lm = @agent_lm }
      agent
    end
  end
end
```

## Usage

```bash
# Single command - optimizer runs as async background task
looped

# Interactive session with GEPA learning in background
[looped] Optimizer started (background)
[looped] Agent ready (gen 3, score 0.82)

> Fix the failing test in spec/user_spec.rb
[agent] Reading spec/user_spec.rb...
[agent] Applied fix. Judge score: 0.9

> quit
[looped] Goodbye! State saved to ~/.looped/
```

## Design Decisions

1. **Standalone gem**: `looped` depends on `dspy-rb` and `dspy-gepa`
2. **Sorbet types**: Full `T::Struct` types for all data structures
3. **Sandbox**: Docker containers via `trusted-sandbox` gem for RunCommand
4. **Training data**: Real usage - agent learns from your actual coding tasks
5. **Judge model**: Configurable via `LOOPED_JUDGE_MODEL` env var
6. **GEPA trigger**: Background async task continuously monitors and optimizes
7. **Persistence**: File-based in `~/.looped/`
8. **Concurrency**: Async gem - single command runs both agent and optimizer

## Testing Strategy

1. **Unit tests** for Memory, State, Tools (isolated, fast)
2. **Integration tests** with VCR for Judge and Agent
3. **Smoke test** for GEPA optimization loop
4. **TDD approach**: Write failing tests first, then implement

## Documentation

- `docs/self-improving-coding-agent.md` - Tutorial article explaining the architecture step-by-step
