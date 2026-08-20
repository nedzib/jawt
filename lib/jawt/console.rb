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
      @mode = :list
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
      if @mode != :list
        @mode = :list if key && !QUIT_KEYS.include?(key)
        return
      end

      case key
      when "r", "R" then run_selected
      when "g", "G" then @mode = :graph
      when "l", "L" then @mode = :logs
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
      case @mode
      when :graph then render_graph
      when :logs then render_logs
      else render_list
      end
    end

    def render_list
      workflows = @client.request("list")
      runs = @client.request("runs")
      latest = runs.first

      @selected = @selected % workflows.size unless workflows.empty?
      next_name = next_in_queue(workflows)

      out = [bold(cyan("JAWT console"))]
      out << ""
      out << bold("Workflows:")
      workflows.each_with_index do |wf, i|
        out << workflow_line(wf, i, next_name)
        if i == @selected && !wf["valid"]
          wf["errors"].each { |e| out << "        #{red('- ' + e)}" }
        end
      end
      out << ""
      out << bold("Runs:")
      runs.first(5).each { |run| out << run_line(run) }
      out << ""
      out << bold("Logs (#{latest ? latest['id'] : 'ninguno'}):")
      if latest
        @client.request("logs", "run_id" => latest["id"]).last(5).each { |l| out << "  #{dim(l)}" }
      end
      out << ""
      out << dim("[r] ejecutar   [g] grafo   [l] logs   [↑/↓] mover   [q / Ctrl-C] salir")
      $stdout.print(CLEAR)
      $stdout.print(out.join("\r\n"))
      $stdout.flush
    end

    def render_graph
      workflows = @client.request("list")
      if workflows.empty?
        @mode = :list
        return
      end

      wf = workflows[@selected % workflows.size]
      graph = @client.request("graph", "path" => wf["path"])

      $stdout.print(CLEAR)
      $stdout.print(bold(cyan("Grafo: #{wf['name']}")) + "\r\n\r\n")
      if graph && !graph.empty?
        $stdout.print(graph.gsub("\n", "\r\n") + "\r\n")
      else
        $stdout.print(red("no se pudo generar el grafo (workflow inválido)") + "\r\n")
      end
      $stdout.print("\r\n" + dim("cualquier tecla para volver · q / Ctrl-C para salir") + "\r\n")
      $stdout.flush
    end

    def render_logs
      runs = @client.request("runs")
      latest = runs.first

      out = [bold(cyan("JAWT · runs y logs completos"))]
      out << ""
      out << bold("Runs (#{runs.size}):")
      runs.each { |run| out << run_line(run) }
      out << ""
      out << bold("Logs (#{latest ? latest['id'] : 'ninguno'}):")
      if latest
        @client.request("logs", "run_id" => latest["id"]).each { |l| out << "  #{dim(l)}" }
      end
      out << ""
      out << dim("cualquier tecla para volver · q / Ctrl-C para salir")
      $stdout.print(CLEAR)
      $stdout.print(out.join("\r\n"))
      $stdout.flush
    end

    def workflow_line(wf, index, next_name)
      selected = index == @selected
      cursor = selected ? ">" : " "
      mark = wf["valid"] ? green("✓") : red("✗")

      name = wf["name"]
      name = bold(cyan(name)) if selected
      repo = File.basename(wf["repo"].to_s)
      label = repo.empty? ? name : "#{name} #{dim("(#{repo})")}"

      line = "  #{cursor} #{mark} #{label}"
      sched = schedule_text(wf)
      line += "   #{dim(sched)}" unless sched.empty?
      line += "   #{bold(magenta('<< siguiente'))}" if wf["name"] == next_name
      line += "   #{yellow('(ejecutando)')}" if wf["running"]
      line
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
      case run["status"]
      when "running" then "#{yellow('●')} #{run['id']}  #{run['workflow']}  #{yellow('running')}"
      when "success" then "#{green('✓')} #{run['id']}  #{run['workflow']}  #{green('success')}"
      when "failed"  then "#{red('✗')} #{run['id']}  #{run['workflow']}  #{red('failed')}"
      else "  #{run['id']}  #{run['workflow']}  #{run['status']}"
      end
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
      latest = runs.first
      next_name = next_in_queue(workflows)

      puts bold("Workflows:")
      workflows.each do |wf|
        mark = wf["valid"] ? green("✓") : red("✗")
        extra = [schedule_text(wf), (wf["name"] == next_name ? "siguiente" : nil)]
                .compact.join(" · ")
        line = "  #{mark} #{display_name(wf)}"
        line += "   #{dim(extra)}" unless extra.empty?
        puts line
        wf["errors"].each { |e| puts "      #{red('- ' + e)}" } unless wf["valid"]
      end
      puts
      puts bold("Runs:")
      runs.each { |run| puts run_line(run) }
      puts
      puts bold("Logs (#{latest ? latest['id'] : 'ninguno'}):")
      if latest
        @client.request("logs", "run_id" => latest["id"]).last(15).each { |l| puts "  #{l}" }
      end
    end

    def display_name(wf)
      repo = File.basename(wf["repo"].to_s)
      repo.empty? ? wf["name"] : "#{wf['name']} (#{repo})"
    end

    def colorize?
      $stdout.tty?
    end

    def ansi(code, text)
      colorize? ? "\e[#{code}m#{text}\e[0m" : text
    end

    def green(text)
      ansi("32", text)
    end

    def red(text)
      ansi("31", text)
    end

    def yellow(text)
      ansi("33", text)
    end

    def cyan(text)
      ansi("36", text)
    end

    def magenta(text)
      ansi("35", text)
    end

    def dim(text)
      ansi("2", text)
    end

    def bold(text)
      ansi("1", text)
    end
  end
end
