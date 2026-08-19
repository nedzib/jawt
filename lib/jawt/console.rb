# frozen_string_literal: true

require "io/console"

module Jawt
  class Console
    REFRESH = 0.25
    ALT_ENTER = "\e[?1049h"
    ALT_LEAVE = "\e[?1049l"
    CLEAR = "\e[H\e[2J"
    QUIT_KEYS = ["q", "Q", "\u0003", "\x03"].freeze

    def initialize(client)
      @client = client
      @selected = 0
    end

    def run(once: false)
      raise "el daemon no está corriendo (ejecuta 'jawt daemon start')" unless @client.connected?

      once ? render_once : fullscreen_loop
    end

    private

    def fullscreen_loop
      $stdout.print(ALT_ENTER)
      $stdin.raw!
      loop do
        render_fullscreen
        key = read_key
        handle_key(key)
        break if QUIT_KEYS.include?(key)
      end
    rescue Interrupt
      nil
    rescue StandardError => e
      @fatal = e.message.empty? ? "error en la consola" : e.message
    ensure
      $stdin.cooked!
      $stdout.print(ALT_LEAVE)
      puts @fatal if @fatal
    end

    def read_key
      return nil unless IO.select([$stdin], nil, nil, REFRESH)

      $stdin.read_nonblock(10)
    rescue IO::WaitReadable, EOFError
      nil
    end

    def handle_key(key)
      case key
      when "r", "R" then run_selected
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

    def render_fullscreen
      workflows = @client.request("list")
      runs = @client.request("runs")
      latest = runs.first

      @selected = @selected % workflows.size unless workflows.empty?
      next_name = next_in_queue(workflows)

      out = [CLEAR]
      out << "JAWT console"
      out << ""
      out << "Workflows:"
      workflows.each_with_index do |wf, i|
        out << workflow_line(wf, i, next_name)
        if i == @selected && !wf["valid"]
          wf["errors"].each { |e| out << "        - #{e}" }
        end
      end
      out << ""
      out << "Runs:"
      runs.each { |run| out << run_line(run) }
      out << ""
      out << "Logs (#{latest ? latest['id'] : 'ninguno'}):"
      if latest
        @client.request("logs", "run_id" => latest["id"]).last(15).each { |l| out << "  #{l}" }
      end
      out << ""
      out << "[r] ejecutar seleccionado   [↑/↓] mover   [q / Ctrl-C] salir"
      $stdout.print(out.join("\n"))
      $stdout.flush
    end

    def workflow_line(wf, index, next_name)
      cursor = index == @selected ? ">" : " "
      mark = wf["valid"] ? "✓" : "✗"
      name = display_name(wf)

      line = "  #{cursor} #{mark} #{name}"
      line += "   #{schedule_text(wf)}" unless schedule_text(wf).empty?
      line += "   << siguiente" if wf["name"] == next_name
      line += "   (ejecutando)" if wf["running"]
      line
    end

    def display_name(wf)
      repo = File.basename(wf["repo"].to_s)
      repo.empty? ? wf["name"] : "#{wf['name']} (#{repo})"
    end

    def schedule_text(wf)
      return "" unless wf["scheduled"]
      return "programado" unless wf["schedule_every"]

      "cada #{format_interval(wf['schedule_every'])} · próximo en #{format_due_in(wf['due_in'])}"
    end

    def next_in_queue(workflows)
      scheduled = workflows.select do |w|
        w["scheduled"] && w["valid"] && !w["running"] && w.key?("due_in")
      end
      return nil if scheduled.empty?

      scheduled.min_by { |w| w["due_in"] }["name"]
    end

    def run_line(run)
      mark = { "running" => "●", "success" => "✓", "failed" => "✗" }[run["status"]] || " "
      "  #{mark} #{run['id']}  #{run['workflow']}  #{run['status']}"
    end

    def format_interval(seconds)
      return "#{seconds}s" if seconds < 60
      return "#{seconds / 60}m" if seconds < 3600
      return "#{seconds / 3600}h" if seconds < 86_400

      "#{seconds / 86_400}d"
    end

    def format_due_in(seconds)
      return "ahora" if seconds.to_i <= 0

      h = seconds / 3600
      m = (seconds % 3600) / 60
      s = seconds % 60
      return "#{h}h #{m}m" if h.positive?
      return "#{m}m #{s}s" if m.positive?

      "#{s}s"
    end

    def render_once
      workflows = @client.request("list")
      runs = @client.request("runs")
      next_name = next_in_queue(workflows)

      puts "Workflows:"
      workflows.each do |wf|
        mark = wf["valid"] ? "✓" : "✗"
        extra = [schedule_text(wf), (wf["name"] == next_name ? "siguiente" : nil)]
                .compact.join(" · ")
        line = "  #{mark} #{display_name(wf)}"
        line += "   #{extra}" unless extra.empty?
        puts line
        wf["errors"].each { |e| puts "      - #{e}" } unless wf["valid"]
      end
      puts
      puts "Runs:"
      runs.each { |run| puts run_line(run) }
    end
  end
end
