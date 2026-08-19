# frozen_string_literal: true

require "toml-rb"
require "fileutils"

module Jawt
  class Config
    DEFAULT_PATH = File.join(Dir.home, ".config", "jawt", "config.toml")

    attr_reader :path, :repos

    def initialize(path: DEFAULT_PATH, repos: [])
      @path = path
      @repos = Array(repos).map { |r| File.expand_path(r.to_s) }.uniq
    end

    def self.load(path = DEFAULT_PATH)
      return new(path: path) unless File.exist?(path)

      data = TomlRB.load_file(path)
      new(path: path, repos: data["repos"])
    end

    def workflow_dirs
      dirs = repos.map { |r| File.join(r, ".jawt", "workflows") }
      dirs << File.join(Dir.pwd, ".jawt", "workflows")
      dirs.uniq
    end

    def add_repo(dir)
      expanded = File.expand_path(dir)
      @repos << expanded unless @repos.include?(expanded)
      save
      expanded
    end

    def remove_repo(dir)
      expanded = File.expand_path(dir)
      @repos.delete(expanded)
      save
      expanded
    end

    def save
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, TomlRB.dump("repos" => repos))
    end
  end
end
