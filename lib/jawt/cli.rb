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
      workflows = workflow_files(argv.first)
      all_ok = true

      workflows.each do |name, path|
        workflow = Workflow.from_yaml(File.read(path))
        result = Validator.new(registry).validate(workflow)
        if result.ok?
          puts green("OK") + "  #{name}"
        else
          all_ok = false
          puts red("ERROR") + "  #{name}"
          result.errors.each { |e| puts "    - #{e}" }
        end
      rescue Error => e
        all_ok = false
        puts red("ERROR") + "  #{name}: #{e.message}"
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

    def cmd_status
      puts "workflows: #{workflow_files(nil).size}"
      puts "nodos:     #{Registry.default.names.size}"
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
      puts green("creado") + "  #{manifest}"
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

        [inputs]

        [outputs]

        [ports]
        out = []

        [behavior]
        cardinality = "single"
        on_failure = "stop"
      TOML
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
