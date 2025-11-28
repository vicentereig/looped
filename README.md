# Looped

A self-improving coding agent that learns from its own performance.

[![Gem Version](https://img.shields.io/gem/v/looped)](https://rubygems.org/gems/looped)
[![Build Status](https://img.shields.io/github/actions/workflow/status/vicentereig/looped/ruby.yml?branch=main)](https://github.com/vicentereig/looped/actions)

```
                           ┌─────────────────────────────────────┐
                           │         YOU / YOUR APP              │
                           │   "Write a fibonacci function"      │
                           └──────────────┬──────────────────────┘
                                          │
                                          ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                              LOOPED::AGENT                                   │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                         ReAct Loop (Think → Act → Observe)             │  │
│  │                                                                        │  │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐              │  │
│  │  │    THINK     │───▶│     ACT      │───▶│   OBSERVE    │──┐           │  │
│  │  │  Plan next   │    │  Use tools   │    │   Process    │  │           │  │
│  │  │    step      │    │              │    │   results    │  │           │  │
│  │  └──────────────┘    └──────────────┘    └──────────────┘  │           │  │
│  │         ▲                                                   │           │  │
│  │         └───────────────────────────────────────────────────┘           │  │
│  │                        (repeat until solved)                            │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  Tools: read_file │ write_file │ search_code │ run_command                   │
└──────────────────────────────────────────────────────────────────────────────┘
                                          │
                                          ▼ solution
┌──────────────────────────────────────────────────────────────────────────────┐
│                              LOOPED::JUDGE                                   │
│                                                                              │
│   Evaluates: Correctness • Code Quality • Best Practices                     │
│   Returns:   Score (0-10) • Pass/Fail • Critique • Suggestions               │
└──────────────────────────────────────────────────────────────────────────────┘
                                          │
                       ┌──────────────────┴──────────────────┐
                       │                                     │
                       ▼                                     ▼
              ┌────────────────┐                    ┌────────────────────┐
              │  Return to     │                    │  Persist Result    │
              │  User/App      │                    │  to Training       │
              │  with score    │                    │  Buffer            │
              └────────────────┘                    └─────────┬──────────┘
                                                              │
┌─────────────────────────────────────────────────────────────┼────────────────┐
│                          ~/.looped/                         │                │
│                                                             ▼                │
│  instructions.json ◀──────────────────────┐    training_buffer.json         │
│  (current best prompts)                   │    (recent results)              │
│                                           │           │                      │
│  history/                                 │           │ when buffer >= 5     │
│  (archived training data)                 │           ▼                      │
│                                    ┌──────┴───────────────────────┐          │
│                                    │     LOOPED::OPTIMIZER        │          │
│                                    │     (Background Async)       │          │
│                                    │                              │          │
│                                    │  1. Build training examples  │          │
│                                    │  2. Run GEPA optimization    │          │
│                                    │  3. Extract better prompts   │          │
│                                    │  4. Hot-swap instructions    │          │
│                                    └──────────────────────────────┘          │
└──────────────────────────────────────────────────────────────────────────────┘
                                          │
                                          │ Agent detects file change
                                          │ and hot-reloads improved
                                          ▼ instructions automatically
                              ┌─────────────────────────┐
                              │  Next task benefits     │
                              │  from learned prompts   │
                              └─────────────────────────┘
```

## Why Looped?

**The Problem:** LLM-based coding agents use static prompts. When they fail or produce suboptimal code, there's no mechanism to learn from those mistakes. You're stuck manually tweaking prompts.

**The Solution:** Looped creates a feedback loop where the agent:
1. Attempts coding tasks using ReAct (Reasoning + Acting)
2. Gets scored by an LLM judge on correctness, quality, and best practices
3. Stores results as training data
4. Automatically optimizes its own prompts using GEPA (Genetic Evolution of Prompt Attributes)
5. Hot-swaps improved prompts without restart

**The Outcome:** An agent that gets measurably better at coding tasks over time, with improvements persisted across sessions.

## Benefits

| Benefit | Description |
|---------|-------------|
| **Self-Improving** | Automatically learns from successes and failures—no manual prompt engineering |
| **Measurable Progress** | Every solution is scored; track improvement over generations |
| **Persistent Learning** | Optimized prompts saved to disk; improvements survive restarts |
| **Zero Configuration** | Works out of the box; optimization runs transparently in background |
| **Multi-Model Support** | Use OpenAI, Anthropic, or Google models for any component |

## Expected Outcomes

When you use Looped over time:

1. **Generation 0 (Initial):** Agent uses default DSPy.rb ReAct prompts
2. **After ~5 tasks:** First optimization cycle runs, prompts refined based on judge feedback
3. **After ~20 tasks:** Multiple optimization generations; agent develops task-specific reasoning patterns
4. **Ongoing:** Continuous improvement as more diverse tasks provide richer training signal

Check progress anytime with the `status` command:
```
looped> status
=== Optimization Status ===
Generation: 3
Best Score: 8.7/10
Training Buffer: 2/5 results
Last Updated: 2024-11-28 12:30:00
```

## Overview

**Looped** is a Ruby gem that creates a coding agent capable of:

1. **Executing coding tasks** using DSPy.rb ReAct with file operations, code search, and command execution
2. **Evaluating its own work** with an LLM-as-judge that scores solutions
3. **Continuously improving** by optimizing prompts with GEPA running in the background
4. **Persisting learning** to disk (`~/.looped/`) for cross-session improvement

## Installation

Add to your Gemfile:

```ruby
gem 'looped'
```

Or install directly:

```bash
gem install looped
```

## Quick Start

### Interactive Mode

```bash
# Set your API key
export OPENAI_API_KEY=sk-...

# Start the interactive agent
looped
```

```
╦  ┌─┐┌─┐┌─┐┌─┐┌┬┐
║  │ ││ │├─┘├┤  ││
╩═╝└─┘└─┘┴  └─┘─┴┘

Self-improving coding agent powered by DSPy.rb + GEPA

Type a coding task and press Enter. Type 'quit' to exit.
Type 'status' to see optimization status.

looped> Write a Ruby function that calculates fibonacci numbers

=== Result ===

Score: 8.5/10

Solution:
def fibonacci(n)
  return n if n <= 1
  fibonacci(n - 1) + fibonacci(n - 2)
end

Feedback:
Score: 8.5/10
Status: PASSED
...
```

### Single Task Mode

```bash
# Run a single task and exit
looped "Fix the syntax error in main.rb"

# With custom model
looped -m openai/gpt-4o "Refactor the User class"

# With context file
looped -c README.md "Add installation instructions"
```

### Programmatic Usage

```ruby
require 'looped'

# Single task execution
result = Looped.execute(
  task: 'Write a function that reverses a string',
  context: 'Use Ruby best practices'
)

puts result.solution    # => "def reverse_string(str)..."
puts result.score       # => 8.5
puts result.feedback    # => "Score: 8.5/10..."

# Or use the agent directly
agent = Looped::Agent.new(model: 'openai/gpt-4o')
result = agent.run(task: 'Create a binary search function')
```

## Available Tools

The agent has access to four tools:

| Tool | Description |
|------|-------------|
| `read_file` | Read contents of a file |
| `write_file` | Write content to a file |
| `search_code` | Search for patterns in code using ripgrep |
| `run_command` | Execute shell commands |

## CLI Reference

```
looped [options] [task]

Options:
    -m, --model MODEL         Agent model (default: openai/gpt-4o-mini)
    -j, --judge-model MODEL   Judge model for evaluation
    -r, --reflection-model MODEL  GEPA reflection model
    -i, --max-iterations N    Max ReAct iterations (default: 10)
    -c, --context FILE        Load context from file
        --no-optimizer        Disable background optimizer
    -v, --version             Show version
    -h, --help                Show this help message

Interactive Commands:
    <task>     Execute a coding task
    status     Show optimization status
    history    Show recent task history
    help       Show help message
    quit       Exit the application
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENAI_API_KEY` | OpenAI API key | (required for openai/* models) |
| `ANTHROPIC_API_KEY` | Anthropic API key | (for anthropic/* models) |
| `GEMINI_API_KEY` | Google API key | (for gemini/* models) |
| `LOOPED_MODEL` | Default agent model | `openai/gpt-4o-mini` |
| `LOOPED_JUDGE_MODEL` | Default judge model | `openai/gpt-4o-mini` |
| `LOOPED_STORAGE_DIR` | Storage directory | `~/.looped` |

### Supported Models

Any model supported by DSPy.rb:

```ruby
# OpenAI
'openai/gpt-4o'
'openai/gpt-4o-mini'

# Anthropic
'anthropic/claude-3-5-sonnet-20241022'
'anthropic/claude-3-haiku-20240307'

# Google
'gemini/gemini-1.5-pro'
'gemini/gemini-1.5-flash'
```

## How It Works

### 1. Task Execution

When you give Looped a task, it uses a ReAct (Reasoning + Acting) loop:

1. **Think**: Analyze the task and plan approach
2. **Act**: Use tools (read/write files, search, run commands)
3. **Observe**: Process tool outputs
4. Repeat until solution is found

### 2. Evaluation

Every solution is evaluated by an LLM judge that scores:
- Correctness
- Code quality
- Best practices adherence

### 3. Learning

Results are stored in a training buffer. When enough results accumulate, the background optimizer:

1. Collects training examples
2. Runs GEPA (Genetic Evolution of Prompt Attributes) optimization
3. Generates improved instructions
4. Hot-swaps the agent's prompts

### 4. Persistence

All state is persisted to `~/.looped/`:
- `instructions.json` - Current optimized prompts
- `training_buffer.json` - Recent results for learning
- `history/` - Archived training data

## Development

```bash
# Clone the repo
git clone https://github.com/vicentereig/looped.git
cd looped

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run with local changes
bundle exec exe/looped
```

## Dependencies

- [dspy](https://rubygems.org/gems/dspy) - Prompt engineering framework
- [dspy-openai](https://rubygems.org/gems/dspy-openai) - OpenAI adapter
- [gepa](https://rubygems.org/gems/gepa) - Genetic prompt optimization
- [async](https://rubygems.org/gems/async) - Concurrent execution
- [sorbet-runtime](https://rubygems.org/gems/sorbet-runtime) - Type checking

## License

MIT License - see [LICENSE.txt](LICENSE.txt)

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Create a Pull Request
