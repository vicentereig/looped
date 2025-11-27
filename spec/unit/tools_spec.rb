# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe 'Looped::Tools' do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe Looped::Tools::ReadFile do
    subject(:tool) { described_class.new }

    it 'has the correct tool name' do
      expect(tool.name).to eq('read_file')
    end

    it 'reads file contents' do
      path = File.join(temp_dir, 'test.txt')
      File.write(path, 'Hello, World!')

      result = tool.call(path: path)
      expect(result).to eq('Hello, World!')
    end

    it 'returns error for non-existent file' do
      result = tool.call(path: '/nonexistent/file.txt')
      expect(result).to include('Error: File not found')
    end

    it 'returns error for permission denied' do
      path = File.join(temp_dir, 'protected.txt')
      File.write(path, 'secret')
      File.chmod(0o000, path)

      result = tool.call(path: path)
      expect(result).to include('Error: Permission denied')
    ensure
      File.chmod(0o644, path) if File.exist?(path)
    end
  end

  describe Looped::Tools::WriteFile do
    subject(:tool) { described_class.new }

    it 'has the correct tool name' do
      expect(tool.name).to eq('write_file')
    end

    it 'writes content to a file' do
      path = File.join(temp_dir, 'output.txt')

      result = tool.call(path: path, content: 'Test content')

      expect(result).to include('Successfully wrote')
      expect(File.read(path)).to eq('Test content')
    end

    it 'creates parent directories if needed' do
      path = File.join(temp_dir, 'nested', 'dir', 'file.txt')

      tool.call(path: path, content: 'Nested content')

      expect(File.exist?(path)).to be true
      expect(File.read(path)).to eq('Nested content')
    end

    it 'returns error for permission denied' do
      protected_dir = File.join(temp_dir, 'protected')
      FileUtils.mkdir_p(protected_dir)
      File.chmod(0o000, protected_dir)

      path = File.join(protected_dir, 'file.txt')
      result = tool.call(path: path, content: 'content')

      expect(result).to include('Error')
    ensure
      File.chmod(0o755, protected_dir) if Dir.exist?(protected_dir)
    end
  end

  describe Looped::Tools::SearchCode do
    subject(:tool) { described_class.new }

    before do
      File.write(File.join(temp_dir, 'app.rb'), "def hello\n  puts 'world'\nend")
      File.write(File.join(temp_dir, 'test.rb'), "def test_hello\n  assert true\nend")
    end

    it 'has the correct tool name' do
      expect(tool.name).to eq('search_code')
    end

    it 'finds matching patterns' do
      result = tool.call(pattern: 'def', path: temp_dir)

      expect(result).to include('def hello')
      expect(result).to include('def test_hello')
    end

    it 'returns no matches message when nothing found' do
      result = tool.call(pattern: 'nonexistent_pattern_xyz', path: temp_dir)
      expect(result).to include('No matches found')
    end

    it 'filters by file type when specified' do
      File.write(File.join(temp_dir, 'readme.md'), '# def not code')

      result = tool.call(pattern: 'def', path: temp_dir, file_type: 'ruby')

      expect(result).to include('def hello')
      expect(result).not_to include('readme.md')
    end
  end

  describe Looped::Tools::RunCommand do
    subject(:tool) { described_class.new }

    it 'has the correct tool name' do
      expect(tool.name).to eq('run_command')
    end

    it 'executes commands and returns output' do
      result = tool.call(command: 'echo "Hello"')

      expect(result).to include('Exit code: 0')
      expect(result).to include('Hello')
    end

    it 'captures exit codes' do
      result = tool.call(command: 'exit 1')
      expect(result).to include('Exit code: 1')
    end

    it 'times out long-running commands' do
      result = tool.call(command: 'sleep 10', timeout: 1)
      expect(result).to include('Command timed out')
    end

    it 'captures stderr' do
      result = tool.call(command: 'echo "error" >&2')
      expect(result).to include('error')
    end
  end
end
