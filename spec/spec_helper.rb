# frozen_string_literal: true

require 'bundler/setup'

# Load environment before anything else
require 'dotenv'
env_file = File.expand_path('../.env', __dir__)
Dotenv.load(env_file) if File.exist?(env_file)

# Debug: ensure API key is loaded
unless ENV['OPENAI_API_KEY']
  warn "WARNING: OPENAI_API_KEY not found in environment!"
end

require 'vcr'
require 'webmock/rspec'
require 'byebug'

require 'looped'

# Allow net connections for VCR recording
WebMock.allow_net_connect!

# Configure VCR for integration tests
VCR.configure do |config|
  config.cassette_library_dir = 'spec/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter out sensitive API keys
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
  config.filter_sensitive_data('<ANTHROPIC_API_KEY>') { ENV['ANTHROPIC_API_KEY'] }
  config.filter_sensitive_data('<GEMINI_API_KEY>') { ENV['GEMINI_API_KEY'] }
  config.filter_sensitive_data('<OPENROUTER_API_KEY>') { ENV['OPENROUTER_API_KEY'] }

  # Filter out organization headers
  config.filter_sensitive_data('<OPENAI_ORGANIZATION>') do |interaction|
    if interaction.response.headers['Openai-Organization']
      interaction.response.headers['Openai-Organization'].first
    end
  end

  # Redact sensitive headers before recording
  config.before_record do |interaction|
    if interaction.response.headers['Set-Cookie']
      interaction.response.headers['Set-Cookie'] = ['<REDACTED>']
    end

    if interaction.response.headers['Openai-Organization']
      interaction.response.headers['Openai-Organization'] = ['<OPENAI_ORGANIZATION>']
    end

    if interaction.response.headers['X-Request-Id']
      interaction.response.headers['X-Request-Id'] = ['<REQUEST_ID>']
    end
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = 'doc' if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed

  # Use a temp directory for state during tests
  config.around(:each) do |example|
    Dir.mktmpdir('looped_test') do |tmpdir|
      # Override the storage directory via environment variable
      original_storage_dir = ENV['LOOPED_STORAGE_DIR']
      ENV['LOOPED_STORAGE_DIR'] = tmpdir
      example.run
    ensure
      ENV['LOOPED_STORAGE_DIR'] = original_storage_dir
    end
  end
end
