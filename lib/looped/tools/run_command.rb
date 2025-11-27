# typed: strict
# frozen_string_literal: true

require 'open3'
require 'timeout'

module Looped
  module Tools
    class RunCommand < DSPy::Tools::Base
      extend T::Sig

      DEFAULT_TIMEOUT = 30

      tool_name 'run_command'
      tool_description 'Execute a shell command and return its output. Use for running tests, linters, or other development tools.'

      sig { params(command: String, timeout: Integer).returns(String) }
      def call(command:, timeout: DEFAULT_TIMEOUT)
        # TODO: Implement Docker sandbox via trusted-sandbox gem for production
        # For now, basic execution with timeout
        Timeout.timeout(timeout) do
          output, status = Open3.capture2e(command)
          "Exit code: #{status.exitstatus}\n#{output}"
        end
      rescue Timeout::Error
        "Error: Command timed out after #{timeout} seconds"
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end
  end
end
