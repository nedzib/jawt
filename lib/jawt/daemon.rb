# frozen_string_literal: true

require "json"
require "socket"
require "fileutils"

module Jawt
  class Daemon
    WATCH_INTERVAL = 0.5
    DEFAULT_SOCKET = File.join(Dir.home, ".config", "jawt", "daemon.sock")
    DEFAULT_PID = File.join(Dir.home, ".config", "jawt", "daemon.pid")
    LOG_DIR = File.join(Dir.home, ".config", "jawt", "logs")

    Run = Struct.new(:id, :workflow, :status, :started_at, :finished_at,
                     :report, :log, keyword_init: true) do
      def to_h
        {
          "id" => id,
          "workflow" => workflow,
          "status" => status.to_s,
          "started_at" => started_at&.iso8601,
          "finished_at" => finished_at&.iso8601
        }
      end
    end

    Client = Struct.new(:socket, :mutex) do
      def send(obj)
        mutex.synchronize { socket.puts(JSON.generate(obj)) }
      rescue IOError, Errno::EPIPE
        nil
      end
    end

    attr_reader :workflows_dir

    def initialize(workflows_dir: File.join(Dir.pwd, ".jawt", "workflows"),
                   socket_path: DEFAULT_SOCKET, registry: Registry.default)
      @workflows_dir = workflows_dir
      @socket_path = socket_path
      @registry = registry
      @server = nil
      @running = false
      @clients = []
      @runs = {}
      @workflows = {}
      @run_seq = 0
      @mutex = Mutex.new
    end

    def start
      setup_socket
      FileUtils.mkdir_p(LOG_DIR)
      @running = true
      refresh_workflows

      while @running
        if (ready = IO.select([@server], nil, nil, WATCH_INTERVAL))
          ready.first.each { |server| accept_client(server) }
        end
        refresh_workflows
        prune_clients
      end
    ensure
      cleanup
    end

    def stop
      @running = false
    end

    def self.start_daemon(argv = [])
      workflows_dir = File.join(Dir.pwd, ".jawt", "workflows")
      daemon = new(workflows_dir: workflows_dir)
      write_pid
      daemon.start
    end

    def self.write_pid
      FileUtils.mkdir_p(File.dirname(DEFAULT_PID))
      File.write(DEFAULT_PID, Process.pid.to_s)
    end

    def self.clear_pid
      File.delete(DEFAULT_PID) if File.exist?(DEFAULT_PID)
    end

    private

    def setup_socket
      FileUtils.mkdir_p(File.dirname(@socket_path))
      File.unlink(@socket_path) if File.exist?(@socket_path)
      @server = UNIXServer.new(@socket_path)
    end

    def cleanup
      @clients.each { |c| c.socket.close rescue nil }
      @server&.close
      File.unlink(@socket_path) if @socket_path && File.exist?(@socket_path)
      self.class.clear_pid if self.class.respond_to?(:clear_pid)
    rescue StandardError
      nil
    end

    def accept_client(server)
      socket = server.accept
      client = Client.new(socket, Mutex.new)
      @mutex.synchronize { @clients << client }
      Thread.new { handle_client(client) }
    rescue IOError, Errno::EBADF
      nil
    end

    def handle_client(client)
      while (line = client.socket.gets)
        request = JSON.parse(line)
        handle_request(client, request)
        break if request["cmd"] == "stop"
      end
    rescue JSON::ParserError, IOError, EOFError, Errno::EPIPE
      nil
    ensure
      unregister_client(client)
    end

    def unregister_client(client)
      @mutex.synchronize { @clients.delete(client) }
    end

    def prune_clients
      @mutex.synchronize { @clients.reject! { |c| c.socket.closed? } }
    end

    def handle_request(client, request)
      id = request["id"]
      case request["cmd"]
      when "list" then client.send(response(id, true, list_data))
      when "runs" then client.send(response(id, true, runs_data))
      when "run" then client.send(response(id, true, "run_id" => start_run(request["workflow"])))
      when "logs" then client.send(response(id, true, "logs" => logs_for(request["run_id"])))
      when "status" then client.send(response(id, true, daemon_status))
      when "stop" then handle_stop(client, id)
      else client.send(response(id, false, nil, "comando desconocido"))
      end
    end

    def handle_stop(client, id)
      client.send(response(id, true, "stopped" => true))
      @running = false
    end

    def response(id, ok, data = nil, error = nil)
      { "id" => id, "ok" => ok, "data" => data, "error" => error }
    end

    def list_data
      @mutex.synchronize do
        @workflows.values.map do |wf|
          { "name" => wf["name"], "path" => wf["path"], "valid" => wf["valid"], "errors" => wf["errors"] }
        end
      end
    end

    def runs_data
      @mutex.synchronize { @runs.values.sort_by { |r| r.started_at.to_f }.reverse.map(&:to_h) }
    end

    def logs_for(run_id)
      @mutex.synchronize do
        run = @runs[run_id]
        run ? run.log.dup : []
      end
    end

    def daemon_status
      {
        "running" => @running,
        "socket" => @socket_path,
        "workflows" => @workflows.size,
        "runs" => @runs.size
      }
    end

    def start_run(workflow_name)
      workflow = @mutex.synchronize do
        @workflows.values.find { |w| w["name"] == workflow_name.to_s }
      end
      return nil unless workflow

      run_id = next_run_id
      run = Run.new(id: run_id, workflow: workflow_name.to_s, status: :running,
                    started_at: Time.now, finished_at: nil, report: nil, log: [])
      @mutex.synchronize { @runs[run_id] = run }

      Thread.new { execute_run(run, workflow) }
      run_id
    end

    def execute_run(run, workflow)
      broadcast("run_status", "run_id" => run.id, "workflow" => run.workflow, "status" => "running")
      logger = BroadcastLogger.new(self, run.id)

      result = Validator.new(@registry).validate(workflow["workflow"])
      if result.ok?
        report = Runner.new(registry: @registry, logger: logger).run(workflow["workflow"])
        run.status = report.status
        run.report = report
        report.nodes.each_value { |r| record_log(run.id, "#{r.id} #{r.status}") }
      else
        run.status = :failed
        result.errors.each { |e| record_log(run.id, "error: #{e}") }
      end

      run.finished_at = Time.now
      broadcast("run_status", "run_id" => run.id, "workflow" => run.workflow, "status" => run.status.to_s)
    end

    def record_log(run_id, line)
      @mutex.synchronize do
        run = @runs[run_id]
        run.log << line if run
      end
      File.open(File.join(LOG_DIR, "#{run_id}.log"), "a") { |f| f.puts(line) }
      broadcast("log", "run_id" => run_id, "message" => line)
    end

    def broadcast(event, payload)
      message = { "event" => event }.merge(payload)
      @mutex.synchronize { @clients.dup }.each { |client| client.send(message) }
    end

    def next_run_id
      @mutex.synchronize do
        @run_seq += 1
        "run-#{@run_seq}"
      end
    end

    def refresh_workflows
      return unless Dir.exist?(@workflows_dir)

      paths = Dir.glob(File.join(@workflows_dir, "*.workflow")).sort
      current = paths.to_h { |p| [p, File.mtime(p).to_f] }

      changed = current.any? do |path, mtime|
        existing = @mutex.synchronize { @workflows[path] }
        existing.nil? || existing["mtime"] != mtime
      end

      return unless changed

      @mutex.synchronize do
        paths.each do |path|
          reload_workflow(path)
        end
      end
    end

    def reload_workflow(path)
      workflow = Workflow.from_yaml(File.read(path))
      result = Validator.new(@registry).validate(workflow)
      @workflows[path] = {
        "name" => workflow.name,
        "path" => path,
        "workflow" => workflow,
        "valid" => result.ok?,
        "errors" => result.errors,
        "mtime" => File.mtime(path).to_f
      }
    rescue Error => e
      @workflows[path] = {
        "name" => File.basename(path, ".workflow"),
        "path" => path,
        "workflow" => nil,
        "valid" => false,
        "errors" => [e.message],
        "mtime" => File.mtime(path).to_f
      }
    end

    class BroadcastLogger
      def initialize(daemon, run_id)
        @daemon = daemon
        @run_id = run_id
      end

      def log(id, message)
        @daemon.send(:record_log, @run_id, "#{id}: #{message}")
      end

      def entries
        @daemon.send(:logs_for, @run_id)
      end
    end
  end
end
