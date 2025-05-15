# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "rbzk"
  spec.version = "0.1.0"
  spec.authors = [ "Khaled AbuShqear" ]
  spec.email = [ "qmax93@gmail.com" ]

  spec.summary = "Ruby library for ZK biometric devices"
  spec.description = "A Ruby implementation of the ZK protocol for fingerprint and biometric attendance devices"
  spec.homepage = "https://github.com/shqear93/rbzk"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.5.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob(%w[lib/**/*.rb bin/* LICENSE.txt README.md CHANGELOG.md])
  spec.bindir = "bin"
  spec.executables = ["rbzk"]
  spec.require_paths = [ "lib" ]

  # Runtime dependencies
  spec.add_dependency "bytes", "~> 0.1"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "thor", "~> 1.2"
end
