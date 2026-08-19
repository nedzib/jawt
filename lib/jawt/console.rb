# frozen_string_literal: true

require "io/console"

module Jawt
  class Console
    REFRESH = 0.3

    def initialize(client)
      @client = client
      @selected = 0
      @once = false
    end

    def run(once: false)
      @once = once
      raise "el daemon no está corriendo (ejecuta 'jawt daemon start')" unless @client.connected?

      return render_once if once

      interactive_loop
    end

    private

    def interactive_loop
      $stdin.raw!
      loop do
        render
        key = read_key
        handle_key(key)
        break if key == "q"
      end
    ensure
      $stdin.cooked!
      puts
    end

    def read_key
      return nil unless $stdin.ready?

      $stdin.read_nonblock(10)
    rescue IO::WaitReadable, EOFError
      nil
    end

    def handle_key(key)
      case key
      when "q" then nil
      when "r" then run_selected
      when "\e[A", "k" then @selected = [@selected - 1, 0].max
      when "\e[B", "j" then @selected += 1
      end
    end

    def run_selected
      workflows = @client.request("list")
      return if workflows.empty?

      @selected = @selected % workflows.size
      @client.request("run", "path" => workflows[@selected]["path"])
    end

    def render
      workflows = @client.request("list")
      runs = @client.request("runs")
      latest = runs.first

      @selected = @selected % workflows.size unless workflows.empty?

      out = []
      out << "\e[2J\e[H"
      out << "JAWT console"
      out << ""
      out << "Workflows:"
      workflows.each_with_index do |wf, i|
        mark = wf["valid"] ? "✓" : "✗"
        cursor = i == @selected ? ">" : " "
        repo = File.basename(wf["repo"].to_s)
        label = repo.empty? ? wf["name"] : "#{wf['name']} (#{repo})"
        out << "  #{cursor} #{mark} #{label}"
        wf["errors"].each { |e| out << "      - #{e}" } unless wf["valid"]
      end
      out << ""
      out << "Runs:"
      runs.each do |run|
        out << "  #{run['id']}  #{run['workflow']}  #{run['status']}"
      end
      out << ""
      out << "Logs (#{latest ? latest['id'] : 'ninguno'}):"
      if latest
        logs = @client.request("logs", "run_id" => latest["id"])
        logs.last(20).each { |l| out << "  #{l}" }
      end
      out << ""
      out << "[r] ejecutar seleccionado  [↑/↓] mover  [q] salir"
      puts out.join("\n")
    rescue Errno::EPIPE, Errno::ECONNREFUSED
      puts "conexión perdida con el daemon"
      exit 1
    end

    def render_once
      workflows = @client.request("list")
      runs = @client.request("runs")

      puts "Workflows:"
      workflows.each do |wf|
        mark = wf["valid"] ? "✓" : "✗"
        puts "  #{mark} #{wf['name']}"
        wf["errors"].each { |e| puts "      - #{e}" } unless wf["valid"]
      end
      puts
      puts "Runs:"
      runs.each { |run| puts "  #{run['id']}  #{run['workflow']}  #{run['status']}" }
    end
  end
end
