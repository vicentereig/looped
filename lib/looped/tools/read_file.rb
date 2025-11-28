# typed: strict
# frozen_string_literal: true

module Looped
  module Tools
    class ReadFile < DSPy::Tools::Base
      extend T::Sig

      tool_name 'read_file'
      tool_description 'Read contents of a file at the given path'

      sig { params(path: String).returns(String) }
      def call(path:)
        resolved_path = resolve_path(path)
        File.read(resolved_path)
      rescue Errno::ENOENT
        "Error: File not found: #{path}"
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
