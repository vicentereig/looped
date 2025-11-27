# Building a Self-Improving Coding Agent

When you use an LLM-based coding agent, every task generates valuable feedback: what worked, what failed, and why. Most agents throw this data away. **Looped** captures it and uses GEPA to continuously improve your agent's prompts in the background.

This article walks through building a coding agent that gets better the more you use it.

## The Problem

Traditional coding agents have static prompts. You craft instructions once, deploy, and hope for the best. When the agent struggles with certain tasks, you manually tweak prompts based on intuition.

What if the agent could learn from its own performance?

## The Solution: Continuous Prompt Optimization

Looped combines three ideas:

1. **ReAct Agent** - A coding agent with tools (read files, write files, run commands)
2. **LLM-as-Judge** - Every task gets scored and critiqued automatically
3. **GEPA Optimizer** - Runs in the background, improving prompts based on accumulated feedback

```
┌─────────────────────────────────────────────────────────────────┐
│                        You Use The Agent                        │
│  > Fix the failing test in user_spec.rb                        │
│  [agent] Reading file... Found issue... Applied fix.           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ Every task gets judged
┌─────────────────────────────────────────────────────────────────┐
│                         LLM-as-Judge                            │
│  Score: 0.85                                                    │
│  Critique: "Fixed the test but didn't handle edge case X"      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ Results accumulate
┌─────────────────────────────────────────────────────────────────┐
│                    Training Buffer (~/.looped/)                 │
│  [task1, score: 0.9, feedback: "..."]                          │
│  [task2, score: 0.7, feedback: "..."]                          │
│  [task3, score: 0.85, feedback: "..."]                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ Every 60 seconds, GEPA checks
┌─────────────────────────────────────────────────────────────────┐
│                    Background Optimizer                         │
│  "Found 12 results. Running reflection..."                     │
│  "Improvement! 0.82 → 0.89"                                    │
│  → Hot-swaps new instructions into the agent                   │
└─────────────────────────────────────────────────────────────────┘
```

## Step 1: The Simplest Coding Agent

Let's start with a basic ReAct agent that can read and write files:

```ruby
require 'dspy'

class CodingTaskSignature < DSPy::Signature
  description "Complete a coding task."

  input do
    const :task, String
    const :context, String, default: ''
  end

  output do
    const :solution, String
    const :files_modified, T::Array[String]
  end
end

# Define tools
class ReadFileTool < DSPy::Tools::Base
  tool_name 'read_file'
  tool_description 'Read contents of a file'

  sig { params(path: String).returns(String) }
  def call(path:)
    File.read(path)
  rescue => e
    "Error: #{e.message}"
  end
end

class WriteFileTool < DSPy::Tools::Base
  tool_name 'write_file'
  tool_description 'Write content to a file'

  sig { params(path: String, content: String).returns(String) }
  def call(path:, content:)
    File.write(path, content)
    "Wrote #{content.length} bytes to #{path}"
  end
end

# Create the agent
tools = [ReadFileTool.new, WriteFileTool.new]
agent = DSPy::ReAct.new(CodingTaskSignature, tools: tools)

# Use it
result = agent.forward(task: "Add a greeting method to lib/hello.rb")
puts result.solution
```

This works, but the agent never improves. Let's add evaluation.

## Step 2: Add LLM-as-Judge

Every task should be evaluated. We define a Judge signature that scores and critiques:

```ruby
class JudgeSignature < DSPy::Signature
  description "Evaluate code quality and correctness."

  input do
    const :task, String
    const :solution, String
    const :expected_behavior, String
  end

  output do
    const :score, Float           # 0.0 - 1.0
    const :passed, T::Boolean
    const :critique, String       # "Missing edge case handling for..."
    const :suggestions, T::Array[String]
  end
end

class Judge < DSPy::Predict
  def initialize
    super(JudgeSignature)
  end

  def evaluate(task:, solution:, expected_behavior:)
    call(
      task: task,
      solution: solution,
      expected_behavior: expected_behavior
    )
  end
end
```

The critique is crucial—it becomes the feedback that GEPA uses to improve prompts.

## Step 3: Memory with Context Engineering

As the agent works, it accumulates history. But we don't want to dump raw data into the prompt. We use the **two-struct pattern**: rich storage, lean context.

```ruby
# Rich struct for storage (debugging, analytics)
class MemoryEntry < T::Struct
  const :action_type, String
  const :action_input, T::Hash[String, T.untyped]
  const :action_output, String
  const :timestamp, String
  const :model_id, T.nilable(String)
  const :tokens_used, T.nilable(Integer)
end

# Lean struct for prompts (only what the LLM needs)
class ActionSummary < T::Struct
  const :action, String   # "read_file(path=lib/hello.rb)"
  const :result, String   # First 500 chars of output
end
```

The Memory class handles the transformation:

```ruby
class Memory
  def initialize(max_entries: 10)
    @entries = []
    @max_entries = max_entries
  end

  def add(action:, input:, output:)
    @entries << MemoryEntry.new(
      action_type: action,
      action_input: input,
      action_output: output,
      timestamp: Time.now.utc.iso8601
    )
  end

  # Shape into lean context for the LLM
  def to_context
    @entries.last(@max_entries).map do |entry|
      ActionSummary.new(
        action: "#{entry.action_type}(#{summarize(entry.action_input)})",
        result: truncate(entry.action_output, 500)
      )
    end
  end
end
```

## Step 4: Persist Training Data

Every task result needs to be saved so the optimizer can learn from it:

```ruby
class State
  STORAGE_DIR = File.expand_path('~/.looped')

  def append_training_result(result)
    buffer = load_buffer
    buffer << {
      task: result.task,
      solution: result.solution,
      score: result.score,
      feedback: result.feedback,
      timestamp: Time.now.utc.iso8601
    }
    save_buffer(buffer)
  end

  def consume_training_buffer
    buffer = load_buffer
    archive_buffer(buffer)  # Save to history/
    clear_buffer
    buffer
  end
end
```

## Step 5: Background GEPA Optimizer

The magic happens here. A background task monitors the training buffer and runs GEPA when enough data accumulates:

```ruby
class Optimizer
  MIN_BUFFER_SIZE = 10
  POLL_INTERVAL = 60

  def run_forever
    loop do
      check_and_optimize
      sleep POLL_INTERVAL
    end
  end

  private

  def check_and_optimize
    buffer = @state.peek_training_buffer
    return if buffer.size < MIN_BUFFER_SIZE

    puts "[optimizer] Found #{buffer.size} results. Running GEPA..."

    # Convert to DSPy examples
    trainset = buffer.map do |result|
      DSPy::Example.new(
        inputs: { task: result[:task] },
        expected: { expected_behavior: result[:feedback] }
      )
    end

    # Run GEPA
    gepa = DSPy::Teleprompt::GEPA.new(
      metric: create_metric,
      config: { max_metric_calls: 50, minibatch_size: 4 }
    )

    result = gepa.compile(@agent, trainset: trainset)

    if result.best_score_value > current_score
      puts "[optimizer] Improvement! #{current_score} → #{result.best_score_value}"
      save_new_instructions(result.optimized_program)
      notify_agent_to_reload
    end
  end
end
```

## Step 6: Putting It Together with Async

The final piece: run the agent and optimizer together using Ruby's async gem:

```ruby
require 'async'

class Application
  def run
    Async do |task|
      # Background: Optimizer checks every 60s
      optimizer_task = task.async { @optimizer.run_forever }

      # Foreground: Interactive agent
      puts "[looped] Agent ready. Type a task or 'quit' to exit."

      loop do
        print "\n> "
        input = $stdin.gets&.chomp
        break if input.nil? || input == 'quit'

        result = @agent.forward(task: input)
        puts result.solution
      end

      optimizer_task.stop
    end
  end
end

# Run it
Looped.start
```

## How GEPA Improves Prompts

GEPA's reflection loop works like this:

1. **Sample failures** from your training buffer
2. **Show them to a reflection LLM** along with the current instruction
3. **Ask for improvements**: "Given these failures, how should we modify the instruction?"
4. **Test the new instruction** on a validation set
5. **Keep it if it's better** (Pareto frontier prevents regression)

The judge's critique is key. Instead of just "score: 0.7", it provides actionable feedback like:

> "The agent fixed the immediate bug but didn't check for nil values in the input. Consider adding defensive checks."

GEPA's reflection LLM sees this and might propose:

> "When fixing bugs, always check for edge cases like nil inputs, empty arrays, and boundary conditions before applying the fix."

## Usage

```bash
$ looped
[looped] Optimizer started (background)
[looped] Agent ready (gen 1, score 0.75)

> Fix the failing test in spec/user_spec.rb
[agent] Reading spec/user_spec.rb...
[agent] Found assertion failure on line 42...
[agent] Applied fix.

> Add input validation to signup controller
[agent] Reading app/controllers/signup_controller.rb...
...

[optimizer] Found 12 results. Running GEPA...
[optimizer] Improvement! 0.75 → 0.82
[agent] Hot-reloaded instructions (gen 2)

> quit
[looped] Goodbye! State saved to ~/.looped/
```

Over time, the agent learns your codebase patterns, common mistake categories, and effective fix strategies—all automatically.

## Key Takeaways

1. **Capture everything** - Every task generates training data (task, solution, score, critique)

2. **LLM-as-judge provides rich feedback** - Critiques like "missed edge case X" are more useful than bare scores

3. **Background optimization is seamless** - Users don't wait; improvements happen asynchronously

4. **Hot-reload keeps the agent fresh** - New instructions apply immediately without restart

5. **Pareto frontier prevents regression** - GEPA won't accept changes that break previously working cases

## What's Next

- **Sandbox tool execution** - Use Docker for safe command execution
- **Per-tool feedback** - Separate optimization for different tool usage patterns
- **Multi-model routing** - Route complex tasks to stronger models
- **Persistent memory** - Remember context across sessions

The code is available at [github.com/vicentereig/looped](https://github.com/vicentereig/looped).
