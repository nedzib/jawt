# frozen_string_literal: true

require "open3"
require "time"

module Jawt
  class Runner
    NodeResult = Struct.new(:id, :type, :status, :outputs, :active_ports, :error,
                            :duration, :children, keyword_init: true)

    Report = Struct.new(:status, :nodes, :log, keyword_init: true) do
      def failed?
        status == :failed
      end

      def success?
        status == :success
      end
    end

    def initialize(registry:, logger: nil)
      @registry = registry
      @logger = logger || NullLogger.new
    end

    def run(workflow)
      results = {}
      outgoing = Hash.new { |h, k| h[k] = [] }
      pending = Hash.new(0)
      @fan_out = {}

      workflow.edges.each do |edge|
        next unless workflow.node(edge.from.node) && workflow.node(edge.to.node)

        outgoing[edge.from.node] << edge
        pending[edge.to.node] += 1
      end

      start = workflow.start_nodes.first
      queue = [start.id]
      pending[start.id] = 0
      aborted = false

      until queue.empty?
        id = queue.shift
        next if results.key?(id)

        spec = workflow.node(id)
        node = @registry.fetch(spec.type)
        inputs = assemble_inputs(workflow, id, results)
        result = execute(spec, node, inputs, workflow, results)
        results[id] = result

        if result.status == :failed && on_failure(spec, node) == "stop"
          aborted = true
          break
        end

        result.active_ports.each do |port|
          outgoing[id].each do |edge|
            next unless edge.from.port == port

            target = edge.to.node
            pending[target] -= 1
            queue << target if pending[target].zero?
          end
        end
      end

      if aborted
        workflow.nodes.each_key do |id|
          results[id] ||= NodeResult.new(
            id: id, type: workflow.node(id).type, status: :skipped,
            outputs: {}, active_ports: [], error: "abortado", duration: 0.0, children: []
          )
        end
      end

      end_node = workflow.end_nodes.first
      status = if aborted
                 :failed
               elsif end_node && results[end_node.id]&.status == :success
                 :success
               elsif results.values.any? { |r| r.status == :failed }
                 :failed
               else
                 :success
               end

      Report.new(status: status, nodes: results, log: @logger.entries)
    end

    private

    def on_failure(spec, node)
      (spec.config["on_failure"] || spec.config[:on_failure] || node.on_failure).to_s
    end

    def assemble_inputs(workflow, id, results)
      spec = workflow.node(id)
      inputs = stringify_keys(spec.config)
      workflow.incoming_edges(id).each do |edge|
        source = results[edge.from.node]
        next unless source
        next unless source.active_ports.include?(edge.from.port)

        source.outputs.each { |k, v| inputs[k] = v }
      end
      inputs
    end

    def execute(spec, node, inputs, workflow, results)
      items = @fan_out[spec.id]
      return execute_fan_out(spec, node, inputs, workflow, results, items) if items

      execute_once(spec, node, inputs, workflow, results)
    end

    def execute_fan_out(spec, node, inputs, workflow, results, items)
      children = items.map do |item|
        execute_once(spec, node, inputs.merge("item" => item), workflow, results)
      end

      status = children.all? { |c| c.status == :success } ? :success : :failed
      error = children.find(&:error)&.error
      active_ports = status == :success ? ["out"] : (node.port?("error") ? ["error"] : ["out"])

      @logger.log(spec.id, "fan-out #{children.size} elementos")
      NodeResult.new(
        id: spec.id, type: spec.type, status: status,
        outputs: { "items" => children.map(&:outputs) },
        active_ports: active_ports, error: error,
        duration: children.sum(&:duration), children: children
      )
    end

    def execute_once(spec, node, inputs, workflow, results)
      started = Time.now
      outputs = {}
      active_ports = ["out"]
      error = nil
      children = []
      attempts = 0

      begin
        loop do
          attempts += 1
          outputs, active_ports, error, children = dispatch(spec, node, inputs, workflow, results)
          break if error.nil?
          break unless on_failure(spec, node) == "retry" && attempts <= retry_max(spec, node)

          @logger.log(spec.id, "reintento #{attempts}/#{retry_max(spec, node)}")
        end
      rescue StandardError => e
        error = "#{e.class}: #{e.message}"
      end

      status = error.nil? ? :success : :failed
      if error && on_failure(spec, node) == "continue" && node.port?("error")
        active_ports = ["error"]
      end

      @logger.log(spec.id, status.to_s)
      NodeResult.new(
        id: spec.id, type: spec.type, status: status, outputs: outputs,
        active_ports: active_ports, error: error,
        duration: Time.now - started, children: children
      )
    end

    def dispatch(spec, node, inputs, workflow, results)
      case spec.type
      when "start" then run_start(spec, inputs)
      when "end" then run_end
      when "run" then run_command(spec, inputs)
      when "condition" then run_condition(spec, results)
      when "multiplex" then run_multiplex(spec, inputs, workflow, results)
      else [{}, ["out"], nil, []]
      end
    end

    def run_start(spec, inputs)
      context = inputs.any? ? inputs : { "context" => {} }
      [context, ["out"], nil, []]
    end

    def run_end
      [{}, [], nil, []]
    end

    def run_command(spec, inputs)
      command = inputs["command"] || spec.config["command"]
      shell = inputs["shell"] || spec.config["shell"] || ENV["SHELL"] || "/bin/zsh"
      login = inputs.key?("login") ? truthy?(inputs["login"]) : truthy?(spec.config["login"], true)
      interactive = inputs.key?("interactive") ? truthy?(inputs["interactive"]) : truthy?(spec.config["interactive"], true)
      cwd = inputs["cwd"] || spec.config["cwd"] || Dir.pwd
      env = (inputs["env"] || spec.config["env"] || {})

      flags = []
      flags << "-l" if login
      flags << "-i" if interactive
      flags << "-c" << command.to_s

      stdout, stderr, status = Open3.capture3(env, shell, *flags, chdir: cwd)
      exit_code = status.exitstatus || (status.success? ? 0 : 1)

      outputs = { "stdout" => stdout, "stderr" => stderr, "exit_code" => exit_code }
      error = exit_code.zero? ? nil : "el comando terminó con exit code #{exit_code}"
      [outputs, ["out"], error, []]
    end

    def run_condition(spec, results)
      expr = spec.config["when"].to_s
      decision = evaluate(resolve(expr, results))
      [{ "value" => decision }, [decision ? "true" : "false"], nil, []]
    end

    def run_multiplex(spec, inputs, workflow, _results)
      items = Array(inputs["items"] || spec.config["items"] || [])
      downstream = workflow.outgoing_edges(spec.id).select { |e| e.from.port == "out" }
      downstream.each { |edge| @fan_out[edge.to.node] = items }
      [{ "items" => items }, ["out"], nil, []]
    end

    def resolve(str, results)
      str.to_s.gsub(/\$\{([a-zA-Z0-9_.-]+)\}/) do
        ref = Regexp.last_match(1)
        id, field = ref.split(".", 2)
        node_result = results[id]
        if field
          node_result&.outputs&.dig(field).to_s
        else
          node_result&.outputs&.to_s
        end
      end
    end

    def evaluate(expr)
      expr = expr.to_s.strip
      return true if expr == "true"
      return false if expr == "false" || expr.empty?

      op = %w[== != >= <= =~ > <].find { |o| expr.include?(o) }
      raise "expresión no soportada: #{expr}" unless op

      lhs, rhs = expr.split(op, 2).map(&:strip)
      left = coerce(lhs)
      right = coerce(rhs)
      case op
      when "==" then left == right
      when "!=" then left != right
      when ">" then left > right
      when "<" then left < right
      when ">=" then left >= right
      when "<=" then left <= right
      when "=~" then Regexp.new(right).match?(left)
      end
    end

    def coerce(value)
      str = value.to_s.strip
      str = str[1..-2] if (str.start_with?('"') && str.end_with?('"')) ||
                          (str.start_with?("'") && str.end_with?("'"))
      return Integer(str, 10) if str.match?(/\A-?\d+\z/)
      return Float(str) if str.match?(/\A-?\d+\.\d+\z/)

      str
    end

    def retry_max(spec, node)
      value = node.retries.is_a?(Hash) ? node.retries["max"] : 0
      config = spec.config["retry"]
      value = config["max"] if config.is_a?(Hash) && config["max"]
      value.to_i
    end

    def truthy?(value, default = false)
      return default if value.nil?

      value == true || value == "true" || value == 1
    end

    def stringify_keys(hash)
      hash.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
    end

    class NullLogger
      def log(_id, _message); end

      def entries
        []
      end
    end
  end
end
