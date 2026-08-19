# frozen_string_literal: true

require "json"
require "socket"

module Jawt
  class DaemonClient
    def initialize(socket_path: Daemon::DEFAULT_SOCKET)
      @socket_path = socket_path
      @socket = nil
      @reader = nil
      @pending = {}
      @events = Queue.new
      @mutex = Mutex.new
      @seq = 0
    end

    def connect
      @socket = UNIXSocket.new(@socket_path)
      @socket.sync = true
      @reader = Thread.new { read_loop }
      self
    end

    def connected?
      !@socket.nil?
    end

    def request(cmd, **args)
      id = @mutex.synchronize { @seq += 1 }
      queue = Queue.new
      @mutex.synchronize { @pending[id] = queue }
      @socket.puts(JSON.generate({ "id" => id, "cmd" => cmd }.merge(args)))
      resp = queue.pop
      @mutex.synchronize { @pending.delete(id) }
      raise resp["error"] if resp["error"]

      resp["data"]
    end

    def poll_event(timeout: 0.0)
      return @events.pop unless timeout.positive?

      @events.pop(timeout: timeout)
    rescue ThreadError
      nil
    end

    def stop
      request("stop")
    rescue StandardError
      nil
    end

    def close
      @socket&.close
      @reader&.kill
    rescue StandardError
      nil
    end

    private

    def read_loop
      while (line = @socket.gets)
        msg = JSON.parse(line)
        if msg["event"]
          @events << msg
        elsif msg["id"]
          queue = @mutex.synchronize { @pending[msg["id"]] }
          queue << msg if queue
        end
      end
    rescue IOError, Errno::EPIPE, JSON::ParserError
      nil
    ensure
      @mutex.synchronize do
        @pending.each_value { |q| q << { "ok" => false, "error" => "conexión perdida con el daemon" } }
        @pending.clear
      end
    end
  end
end
