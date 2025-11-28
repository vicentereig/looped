# frozen_string_literal: true

require_relative 'lib/looped/version'

Gem::Specification.new do |spec|
  spec.name = 'looped'
  spec.version = Looped::VERSION
  spec.authors = ['Vicente Reig']
  spec.email = ['hey@vicente.services']

  spec.summary = 'Self-improving coding agent with continuous prompt optimization'
  spec.description = 'A coding agent that learns from its own performance using GEPA prompt optimization running in the background.'
  spec.homepage = 'https://github.com/vicentereig/looped'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/vicentereig/looped'
  spec.metadata['changelog_uri'] = 'https://github.com/vicentereig/looped/blob/main/CHANGELOG.md'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = ['looped']
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'async', '~> 2.23'
  spec.add_dependency 'dspy', '~> 0.31.1'
  spec.add_dependency 'dspy-openai', '~> 1.0'
  spec.add_dependency 'dspy-gepa', '~> 1.0.3'
  spec.add_dependency 'gepa', '~> 1.0.2'
  spec.add_dependency 'polars-df', '~> 0.23'
  spec.add_dependency 'sorbet-runtime', '~> 0.5'

  # Development dependencies
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'vcr', '~> 6.2'
  spec.add_development_dependency 'webmock', '~> 3.18'
  spec.add_development_dependency 'byebug', '~> 11.1'
end
