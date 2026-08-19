# frozen_string_literal: true

require_relative "lib/jawt/version"

Gem::Specification.new do |spec|
  spec.name = "jawt"
  spec.version = Jawt::VERSION
  spec.authors = ["Nedzib Sastoque Rangel"]
  spec.email = ["nedzib.sastoque@gmail.com"]

  spec.summary = "JAWT — Just Another Workflow Thing"
  spec.description = "Orquestador de workflows basado en terminal."
  spec.homepage = "https://github.com/nedzib/jawt"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*", "exe/*", "README.md", "LICENSE"]
  spec.bindir = "exe"
  spec.executables = ["jawt"]
  spec.require_paths = ["lib"]

  spec.add_dependency "toml-rb", "~> 4.0"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
