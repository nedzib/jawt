# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class DaemonTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("jawt")
    @workflows_dir = File.join(@dir, "workflows")
    FileUtils.mkdir_p(@workflows_dir)
    @socket = File.join(@dir, "daemon.sock")
    write_workflow("hello", "echo hello")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_daemon_lifecycle
    thread = start_daemon

    client = Jawt::DaemonClient.new(socket_path: @socket).connect

    list = client.request("list")
    assert_equal ["hello"], list.map { |w| w["name"] }
    assert list.first["valid"]

    data = client.request("run", "workflow" => "hello")
    run_id = data["run_id"]
    refute_nil run_id

    wait_for { runs(client).first&.dig("status") != "running" }

    runs = runs(client)
    assert_equal "success", runs.first["status"]

    logs = client.request("logs", "run_id" => run_id)
    refute_empty logs

    client.stop
    thread.join(2)
    refute File.exist?(@socket)
  end

  def test_list_reports_invalid_workflow
    write_workflow("broken", nil)
    thread = start_daemon
    client = Jawt::DaemonClient.new(socket_path: @socket).connect

    list = client.request("list")
    broken = list.find { |w| w["name"] == "broken" }
    refute broken["valid"]
    refute_empty broken["errors"]
  ensure
    client&.stop
    thread&.join(2)
  end

  def test_discovers_workflows_from_multiple_repos
    other_dir = File.join(@dir, "other")
    FileUtils.mkdir_p(other_dir)
    File.write(File.join(other_dir, "review.workflow"), workflow_yaml("review", "echo review"))

    thread = start_daemon([@workflows_dir, other_dir])
    client = Jawt::DaemonClient.new(socket_path: @socket).connect

    names = client.request("list").map { |w| w["name"] }
    assert_includes names, "hello"
    assert_includes names, "review"
  ensure
    client&.stop
    thread&.join(2)
  end

  def test_scheduled_workflow_is_due
    write_workflow("sched", "echo hi")
    File.write(
      File.join(@workflows_dir, "sched.workflow"),
      workflow_yaml("sched", "echo hi", schedule: "1m")
    )

    daemon = Jawt::Daemon.new(workflows_dirs: [@workflows_dir], socket_path: @socket)
    daemon.send(:refresh_workflows)

    due = daemon.send(:due_workflows)
    assert_equal 1, due.size
    assert_includes due.first, "sched.workflow"

    daemon.instance_variable_set(:@last_run, { due.first => Time.now })
    assert_empty daemon.send(:due_workflows)
  end

  def test_deleted_workflow_is_removed
    path = File.join(@workflows_dir, "hello.workflow")
    daemon = Jawt::Daemon.new(workflows_dirs: [@workflows_dir], socket_path: @socket)
    daemon.send(:refresh_workflows)
    assert_equal 1, daemon.instance_variable_get(:@workflows).size

    File.delete(path)
    daemon.send(:refresh_workflows)
    assert_empty daemon.instance_variable_get(:@workflows)
  end

  def test_graph_command
    thread = start_daemon
    client = Jawt::DaemonClient.new(socket_path: @socket).connect

    graph = client.request("graph", "path" => File.join(@workflows_dir, "hello.workflow"))
    assert_includes graph, "start"
    assert_includes graph, "cmd"
  ensure
    client&.stop
    thread&.join(2)
  end

  private

  def start_daemon(dirs = [@workflows_dir])
    daemon = Jawt::Daemon.new(workflows_dirs: dirs, socket_path: @socket)
    thread = Thread.new { daemon.start }
    wait_for { File.exist?(@socket) }
    thread
  end

  def write_workflow(name, command)
    path = File.join(@workflows_dir, "#{name}.workflow")
    if command
      File.write(path, workflow_yaml(name, command))
    else
      File.write(path, "workflow:\n  name: #{name}\n  nodes:\n    start: { type: start }\n")
    end
  end

  def workflow_yaml(name, command, schedule: nil)
    lines = []
    lines << "workflow:"
    lines << "  name: #{name}"
    if schedule
      lines << "  schedule:"
      lines << "    every: #{schedule}"
    end
    lines << "  nodes:"
    lines << "    start: { type: start }"
    lines << "    cmd:"
    lines << "      type: run"
    lines << "      command: \"#{command}\""
    lines << "      shell: /bin/sh"
    lines << "      interactive: false"
    lines << "      login: false"
    lines << "    end: { type: end }"
    lines << "  edges:"
    lines << "    - from: start.out"
    lines << "      to: cmd.in"
    lines << "    - from: cmd.out"
    lines << "      to: end.in"
    lines.join("\n") + "\n"
  end

  def runs(client)
    client.request("runs")
  end

  def wait_for(timeout: 5)
    deadline = Time.now + timeout
    sleep 0.05 until yield || Time.now > deadline
    raise "timeout" unless yield
  end
end
