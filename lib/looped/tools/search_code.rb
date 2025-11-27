# typed: strict
# frozen_string_literal: true

require 'open3'

module Looped
  module Tools
    class SearchCode < DSPy::Tools::Base
      extend T::Sig

      tool_name 'search_code'
      tool_description 'Search for a pattern in code files using ripgrep. Returns matching lines with file paths and line numbers.'

      sig { params(pattern: String, path: String, file_type: T.nilable(String)).returns(String) }
      def call(pattern:, path: '.', file_type: nil)
        cmd = build_command(pattern, path, file_type)
        output, status = Open3.capture2e(*cmd)

        if status.success?
          output.empty? ? "No matches found for: #{pattern}" : output
        else
          "No matches found for: #{pattern}"
        end
      rescue StandardError => e
        "Error: #{e.message}"
      end

      private

      sig { params(pattern: String, path: String, file_type: T.nilable(String)).returns(T::Array[String]) }
      def build_command(pattern, path, file_type)
        cmd = ['rg', '--line-number', '--no-heading', '--max-count', '50', pattern, path]
        cmd += ['--type', file_type] if file_type
        cmd
      end
    end
  end
end
