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
        File.read(path)
      rescue Errno::ENOENT
        "Error: File not found: #{path}"
      rescue Errno::EACCES
        "Error: Permission denied: #{path}"
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end
  end
end
