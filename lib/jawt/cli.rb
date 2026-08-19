# frozen_string_literal: true

require "fileutils"

module Jawt
  class CLI
    WORKFLOW_DIR = ".jawt/workflows"
    USER_DIR = File.join(Dir.home, ".config", "jawt")
    NODES_DIR = File.join(USER_DIR, "nodes")
    CONFIG_PATH = File.join(USER_DIR, "config.toml")

    def self.start(argv)
      new.run(argv)
    end

    def run(argv)
      command = argv.shift
      case command
      when "init" then cmd_init
      when "validate" then cmd_validate(argv)
      when "workflow" then cmd_workflow(argv)
      when "node" then cmd_node(argv)
      when "daemon" then cmd_daemon(argv)
      when "console" then cmd_console(argv)
      when "repo" then cmd_repo(argv)
      when "status" then cmd_status
      when "-v", "--version"
        puts "jawt #{VERSION}"
      when nil, "help", "--help", "-h"
        puts usage
      else
        warn "comando desconocido: #{command}"
        warn usage
        exit 1
      end
    end

    private

    def usage
      <<~TEXT
        jawt #{VERSION}

        Uso:
          jawt init
          jawt validate [workflow]
          jawt workflow create <nombre>
          jawt workflow list
          jawt workflow show <nombre>
          jawt workflow graph <nombre>
          jawt workflow run <nombre>
          jawt workflow edit <nombre>
          jawt node list
          jawt node create <nombre>
          jawt repo add <directorio>
          jawt repo remove <directorio>
          jawt repo list
          jawt daemon start
          jawt daemon stop
          jawt daemon status
          jawt daemon run <workflow>
          jawt console
          jawt status
      TEXT
    end

    def cmd_init
      FileUtils.mkdir_p(WORKFLOW_DIR)
      FileUtils.mkdir_p(NODES_DIR)
      unless File.exist?(CONFIG_PATH)
        File.write(CONFIG_PATH, "# Configuración global de JAWT\n")
      end
      puts green("Inicializado:")
      puts "  repositorio: #{WORKFLOW_DIR}/"
      puts "  nodos:       #{NODES_DIR}/"
    end

    def cmd_validate(argv)
      registry = Registry.default
      workflows = collect_workflows(argv.first)
      all_ok = true

      workflows.each do |wf|
        workflow = Workflow.from_yaml(File.read(wf[:path]))
        result = Validator.new(registry).validate(workflow)
        if result.ok?
          puts green("OK") + "  #{wf[:name]}"
        else
          all_ok = false
          puts red("ERROR") + "  #{wf[:name]}"
          result.errors.each { |e| puts "    - #{e}" }
        end
      rescue Error => e
        all_ok = false
        puts red("ERROR") + "  #{wf[:name]}: #{e.message}"
      end

      exit 1 unless all_ok
    end

    def cmd_workflow(argv)
      sub = argv.shift
      case sub
      when "create" then workflow_create(argv.first)
      when "list" then workflow_list
      when "show" then workflow_show(argv.first)
      when "graph" then workflow_graph(argv.first)
      when "run" then workflow_run(argv.first)
      when "edit" then workflow_edit(argv.first)
      else
        warn "subcomando desconocido: #{sub}"
        exit 1
      end
    end

    def cmd_node(argv)
      sub = argv.shift || "list"
      case sub
      when "list" then node_list
      when "create" then node_create(argv.first)
      when "edit" then node_edit(argv.first)
      else
        warn "subcomando desconocido: #{sub}"
        exit 1
      end
    end

    def cmd_daemon(argv)
      sub = argv.shift || "status"
      case sub
      when "start" then daemon_start
      when "stop" then daemon_stop
      when "status" then daemon_status
      when "run" then daemon_run(argv.first)
      else
        warn "subcomando desconocido: #{sub}"
        exit 1
      end
    end

    def cmd_console(argv)
      once = argv.include?("--once")
      socket = Daemon::DEFAULT_SOCKET

      unless File.exist?(socket)
        warn "el daemon no está corriendo. Ejecuta 'jawt daemon start'"
        exit 1
      end

      client = DaemonClient.new(socket_path: socket).connect
      Console.new(client).run(once: once)
    ensure
      client&.close
    end

    def daemon_start
      if File.exist?(Daemon::DEFAULT_SOCKET)
        puts "el daemon ya está corriendo"
        return
      end

      pid = fork do
        Process.setsid
        $stdin.reopen(File::NULL)
        $stdout.reopen(File::NULL)
        $stderr.reopen(File::NULL)
        Daemon.start_daemon
      end
      Process.detach(pid)
      puts green("daemon iniciado") + "  pid #{pid}"
      puts "socket: #{Daemon::DEFAULT_SOCKET}"
    end

    def daemon_stop
      socket = Daemon::DEFAULT_SOCKET
      unless File.exist?(socket)
        warn "el daemon no está corriendo"
        return
      end

      DaemonClient.new(socket_path: socket).connect.stop
      puts green("daemon detenido")
    rescue Errno::ENOENT, Errno::ECONNREFUSED, Errno::EPIPE
      warn "no se pudo detener el daemon"
    end

    def daemon_status
      socket = Daemon::DEFAULT_SOCKET
      unless File.exist?(socket)
        puts "daemon: no corriendo"
        return
      end

      client = DaemonClient.new(socket_path: socket).connect
      data = client.request("status")
      puts "daemon: corriendo"
      puts "  workflows: #{data['workflows']}"
      puts "  runs:      #{data['runs']}"
    rescue Errno::ENOENT, Errno::ECONNREFUSED
      puts "daemon: no corriendo"
    ensure
      client&.close
    end

    def daemon_run(name)
      abort "faltan argumentos: jawt daemon run <workflow>" if name.to_s.empty?

      socket = Daemon::DEFAULT_SOCKET
      abort "el daemon no está corriendo (ejecuta 'jawt daemon start')" unless File.exist?(socket)

      client = DaemonClient.new(socket_path: socket).connect
      data = client.request("run", "workflow" => name)
      puts "ejecutando '#{name}' -> #{data['run_id']}"
    rescue Errno::ENOENT, Errno::ECONNREFUSED
      abort "el daemon no está corriendo"
    rescue RuntimeError => e
      abort e.message
    ensure
      client&.close
    end

    def cmd_repo(argv)
      sub = argv.shift || "list"
      case sub
      when "add" then repo_add(argv.first)
      when "remove" then repo_remove(argv.first)
      when "list" then repo_list
      else
        warn "subcomando desconocido: #{sub}"
        exit 1
      end
    end

    def repo_add(path)
      abort "faltan argumentos: jawt repo add <directorio>" if path.to_s.empty?

      config = Config.load
      config.add_repo(path)
      puts green("agregado") + "  #{File.expand_path(path)}"
    end

    def repo_remove(path)
      abort "faltan argumentos: jawt repo remove <directorio>" if path.to_s.empty?

      config = Config.load
      config.remove_repo(path)
      puts green("eliminado") + "  #{File.expand_path(path)}"
    end

    def repo_list
      Config.load.repos.each { |r| puts r }
    end

    def cmd_status
      config = Config.load
      puts "repos:"
      config.repos.each { |r| puts "  #{r}" }
      puts "workflows: #{collect_workflows.size}"
      puts "nodos:     #{Registry.default.names.size}"
    end

    def collect_workflows(name = nil)
      Config.load.workflow_dirs.flat_map do |dir|
        next [] unless Dir.exist?(dir)

        pattern = name ? File.join(dir, "#{name.sub(/\.workflow\z/, '')}.workflow") : File.join(dir, "*.workflow")
        Dir.glob(pattern)
      end.map do |path|
        { name: display_name(path), path: path }
      end
    end

    def display_name(path)
      name = File.basename(path, ".workflow")
      repo = File.basename(File.dirname(File.dirname(File.dirname(path))))
      repo == "." || repo == File.basename(Dir.pwd) ? name : "#{name} (#{repo})"
    end

    def workflow_create(name)
      abort "faltan argumentos: jawt workflow create <nombre>" if name.to_s.empty?

      path = workflow_path(name)
      abort "el workflow '#{name}' ya existe" if File.exist?(path)

      FileUtils.mkdir_p(WORKFLOW_DIR)
      File.write(path, template(name))
      puts green("creado") + "  #{path}"
    end

    def workflow_list
      workflow_files(nil).each_key { |name| puts name }
    end

    def workflow_show(name)
      workflow = load_workflow(name)
      puts "nombre:      #{workflow.name}"
      puts "descripción: #{workflow.description}" unless workflow.description.empty?
      puts "requiere:    #{workflow.requires.join(', ')}" unless workflow.requires.empty?
      puts "nodos:"
      workflow.nodes.each_value { |n| puts "  #{n.id}  (#{n.type})" }
      puts "conexiones:"
      workflow.edges.each { |e| puts "  #{e.from.node}.#{e.from.port} -> #{e.to.node}.#{e.to.port}" }
    end

    def workflow_graph(name)
      workflow = load_workflow(name)
      puts Graph.new(workflow).render
    end

    def workflow_run(name)
      workflow = load_workflow(name)
      registry = Registry.default
      result = Validator.new(registry).validate(workflow)
      unless result.ok?
        puts red("workflow inválido:")
        result.errors.each { |e| puts "  - #{e}" }
        exit 1
      end

      runner = Runner.new(registry: registry, logger: Logger.new(quiet: true))
      report = runner.run(workflow)

      puts
      workflow.nodes.each_key do |id|
        r = report.nodes[id]
        next unless r

        mark = status_mark(r.status)
        puts "#{mark} #{id} (#{r.type}) #{format_duration(r.duration)}"
        puts "     error: #{r.error}" if r.error
      end
      puts
      puts report.success? ? green("workflow terminó con éxito") : red("workflow falló")
      exit 1 unless report.success?
    end

    def workflow_edit(name)
      path = workflow_path(name)
      abort "workflow '#{name}' no existe" unless File.exist?(path)

      editor = ENV["EDITOR"] || "vim"
      system(editor, path)
    end

    def node_list
      user = Registry.user_nodes
      Registry.default.names.each do |name|
        source = user.key?(name) ? "usuario" : "base"
        puts "#{name.ljust(12)} (#{source})"
      end
    end

    def node_create(name)
      abort "faltan argumentos: jawt node create <nombre>" if name.to_s.empty?

      dir = File.join(NODES_DIR, name)
      abort "el nodo '#{name}' ya existe" if Dir.exist?(dir)

      FileUtils.mkdir_p(dir)
      manifest = File.join(dir, "node.toml")
      File.write(manifest, node_template(name))
      script = File.join(dir, "main.sh")
      File.write(script, node_script_template)
      File.chmod(0o755, script)
      puts green("creado") + "  #{manifest}"
      puts "  #{script}"
    end

    def node_edit(name)
      path = File.join(NODES_DIR, name, "node.toml")
      abort "el nodo '#{name}' no existe" unless File.exist?(path)

      editor = ENV["EDITOR"] || "vim"
      system(editor, path)
    end

    def load_workflow(name)
      abort "faltan argumentos: nombre del workflow" if name.to_s.empty?

      path = workflow_path(name)
      abort "workflow '#{name}' no existe" unless File.exist?(path)

      Workflow.from_yaml(File.read(path))
    rescue Error => e
      abort "workflow inválido: #{e.message}"
    end

    def workflow_path(name)
      n = name.to_s.sub(/\.workflow\z/, "")
      File.join(WORKFLOW_DIR, "#{n}.workflow")
    end

    def workflow_files(name)
      return { name.sub(/\.workflow\z/, "") => workflow_path(name) } if name

      Dir.glob(File.join(WORKFLOW_DIR, "*.workflow")).to_h do |path|
        [File.basename(path, ".workflow"), path]
      end
    end

    def template(name)
      <<~YAML
        workflow:
          name: #{name}
          description: ""

          requires: [run]

          nodes:
            start: { type: start }
            end: { type: end }

          edges:
            - from: start.out
              to: end.in
      YAML
    end

    def node_template(name)
      <<~TOML
        name = "#{name}"
        description = ""
        exec = "main.sh"

        [inputs]

        [outputs]

        [ports]
        out = []

        [behavior]
        cardinality = "single"
        on_failure = "stop"
      TOML
    end

    def node_script_template
      <<~SH
        #!/bin/sh
        # Entrada: variables JAWT_INPUT_* y JSON en stdin.
        # Salida: un objeto JSON con los outputs declarados en node.toml.
        echo '{}'
      SH
    end

    def status_mark(status)
      case status
      when :success then green("✓")
      when :failed then red("✗")
      when :skipped then yellow("·")
      else " "
      end
    end

    def format_duration(seconds)
      "(%0.3fs)" % seconds
    end

    def colorize?
      $stdout.tty?
    end

    def green(text) = colorize? ? "\e[32m#{text}\e[0m" : text
    def red(text) = colorize? ? "\e[31m#{text}\e[0m" : text
    def yellow(text) = colorize? ? "\e[33m#{text}\e[0m" : text
  end
end
