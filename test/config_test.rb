# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class ConfigTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("jawt-config")
    @path = File.join(@dir, "config.toml")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_load_missing_file_returns_empty
    config = Jawt::Config.load(@path)
    assert_empty config.repos
  end

  def test_add_and_remove_repo
    config = Jawt::Config.new(path: @path)
    config.add_repo("/foo/bar")
    assert_equal ["/foo/bar"], config.repos

    config.remove_repo("/foo/bar")
    assert_empty config.repos
  end

  def test_roundtrip_through_file
    config = Jawt::Config.new(path: @path)
    config.add_repo("/proj/a")
    config.add_repo("/proj/b")

    reloaded = Jawt::Config.load(@path)
    assert_equal ["/proj/a", "/proj/b"], reloaded.repos
  end

  def test_workflow_dirs_includes_repos_and_cwd
    config = Jawt::Config.new(path: @path, repos: ["/proj/a"])
    dirs = config.workflow_dirs
    assert_includes dirs, "/proj/a/.jawt/workflows"
    assert_includes dirs, File.join(Dir.pwd, ".jawt", "workflows")
  end
end
