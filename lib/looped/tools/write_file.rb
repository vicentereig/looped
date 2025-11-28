# typed: strict
# frozen_string_literal: true

require 'fileutils'

module Looped
  module Tools
    class WriteFile < DSPy::Tools::Base
      extend T::Sig

      tool_name 'write_file'
      tool_description 'Write content to a file at the given path. Creates parent directories if needed.'

      sig { params(path: String, content: String).returns(String) }
      def call(path:, content:)
        resolved_path = resolve_path(path)
        FileUtils.mkdir_p(File.dirname(resolved_path))
        File.write(resolved_path, content)
        "Successfully wrote #{content.length} bytes to #{path}"
      rescue Errno::EACCES
        "Error: Permission denied: #{path}"
      rescue StandardError => e
        "Error: #{e.message}"
      end

      private

      sig { params(path: String).returns(String) }
      def resolve_path(path)
        sandbox = ENV['LOOPED_SANDBOX_DIR']
        return path if sandbox.nil? || path.start_with?('/')

        File.join(sandbox, path)
      end
    end
  end
end
