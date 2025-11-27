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
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
        "Successfully wrote #{content.length} bytes to #{path}"
      rescue Errno::EACCES
        "Error: Permission denied: #{path}"
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end
  end
end
