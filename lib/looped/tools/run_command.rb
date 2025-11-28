# typed: strict
# frozen_string_literal: true

require 'open3'

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
        pid = T.let(nil, T.nilable(Integer))
        output = +''

        begin
          stdin, stdout_err, wait_thr = Open3.popen2e(command)
          pid = wait_thr.pid
          stdin.close

          # Wait for process with timeout using a thread
          reader = Thread.new { stdout_err.read }

          if wait_thr.join(timeout)
            # Process completed in time
            output = reader.value
            exit_status = wait_thr.value
            "Exit code: #{exit_status.exitstatus}\n#{output}"
          else
            # Timeout - kill the process
            reader.kill
            Process.kill('TERM', pid)
            sleep 0.1
            begin
              Process.kill('KILL', pid) if wait_thr.alive?
            rescue Errno::ESRCH
              # Process already dead
            end
            wait_thr.join
            "Error: Command timed out after #{timeout} seconds"
          end
        rescue StandardError => e
          "Error: #{e.message}"
        ensure
          stdout_err&.close rescue nil
        end
      end
    end
  end
end
