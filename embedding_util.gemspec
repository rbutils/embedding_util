# frozen_string_literal: true

require_relative "lib/embedding_util/version"

Gem::Specification.new do |spec|
  spec.name = "embedding_util"
  spec.version = EmbeddingUtil::VERSION
  spec.authors = ["hmdne"]
  spec.email = ["54514036+hmdne@users.noreply.github.com"]

  spec.summary = "Local-first text embeddings and reranking for Ruby"
  spec.description = "A small rbutils gem for computing embeddings and true reranking through local embedding model runtimes."
  spec.homepage = "https://github.com/rbutils/embedding_util"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"] = "https://github.com/rbutils/embedding_util"
  spec.metadata["changelog_uri"] = "https://github.com/rbutils/embedding_util/blob/master/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/rbutils/embedding_util#readme"
  spec.metadata["bug_tracker_uri"] = "https://github.com/rbutils/embedding_util/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  tracked_files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL, &:read)&.split("\x0")
  tracked_files&.reject!(&:empty?)
  if tracked_files.nil? || tracked_files.empty?
    tracked_files = Dir.glob("**/*", File::FNM_DOTMATCH, base: __dir__).select do |file|
      next false if %w[. ..].include?(file)

      File.file?(File.join(__dir__, file))
    end
  end

  spec.files = tracked_files.reject do |file|
    (file == gemspec) || file.end_with?(".gem") || file.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile coverage/ pkg/ tmp/ .bundle/ .ruby-lsp/])
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |file| File.basename(file) }
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"
end
