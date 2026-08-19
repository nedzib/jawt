# frozen_string_literal: true

require "toml-rb"

module Jawt
  class Node
    attr_reader :name, :description, :inputs, :outputs, :ports,
                :cardinality, :on_failure, :retries, :dir, :exec

    def initialize(name:, description: "", inputs: {}, outputs: {}, ports: {},
                   cardinality: "single", on_failure: "stop", retries: nil,
                   dir: nil, exec: nil)
      @name = name.to_s
      @description = description.to_s
      @inputs = normalize_inputs(inputs)
      @outputs = outputs.transform_keys(&:to_s)
                        .transform_values { |t| Type.parse(t) }
      @ports = ports.transform_keys(&:to_s)
                    .transform_values { |v| Array(v).map(&:to_s) }
      @cardinality = cardinality.to_s
      @on_failure = on_failure.to_s
      @retries = retries
      @dir = dir
      @exec = exec
    end

    def input(name)
      inputs[name.to_s]
    end

    def port_outputs(port)
      ports.fetch(port.to_s, [])
    end

    def port?(port)
      ports.key?(port.to_s)
    end

    def output?(name)
      outputs.key?(name.to_s)
    end

    def output_type(name)
      outputs[name.to_s]
    end

    def array_output?
      outputs.values.any?(&:array?)
    end

    def self.from_toml(path)
      data = TomlRB.load_file(path)
      behavior = data["behavior"] || {}
      new(
        name: data["name"],
        description: data["description"],
        inputs: data["inputs"] || {},
        outputs: data["outputs"] || {},
        ports: data["ports"] || {},
        cardinality: behavior["cardinality"] || "single",
        on_failure: behavior["on_failure"] || "stop",
        retries: behavior["retry"],
        dir: File.dirname(path),
        exec: data["exec"]
      )
    end

    private

    def normalize_inputs(raw)
      raw.each_with_object({}) do |(name, spec), acc|
        key = name.to_s
        if spec.is_a?(Hash)
          type = Type.parse(spec["type"] || spec[:type] || "any")
          required = spec["required"] || spec[:required] || false
          acc[key] = { type: type, required: required }
        else
          acc[key] = { type: Type.parse(spec), required: false }
        end
      end
    end
  end

  module Builtins
    def self.all
      {
        "start" => Node.new(
          name: "start",
          description: "Entrada del workflow",
          outputs: { "context" => "object" },
          ports: { "out" => ["context"] }
        ),
        "end" => Node.new(
          name: "end",
          description: "Fin del workflow"
        ),
        "condition" => Node.new(
          name: "condition",
          description: "Evalúa una expresión y enruta",
          inputs: { "value" => { type: "any", required: false } },
          outputs: { "value" => "any" },
          ports: { "true" => ["value"], "false" => ["value"] }
        ),
        "multiplex" => Node.new(
          name: "multiplex",
          description: "Distribuye un array elemento a elemento",
          inputs: { "items" => { type: "array<any>", required: true } },
          outputs: { "item" => "any" },
          ports: { "out" => ["item"] },
          cardinality: "array"
        ),
        "run" => Node.new(
          name: "run",
          description: "Ejecuta un comando en el shell",
          inputs: {
            "command" => { type: "string", required: true },
            "args" => { type: "array<string>", required: false },
            "cwd" => { type: "string", required: false },
            "env" => { type: "object", required: false },
            "shell" => { type: "string", required: false },
            "interactive" => { type: "boolean", required: false },
            "login" => { type: "boolean", required: false }
          },
          outputs: {
            "stdout" => "string",
            "stderr" => "string",
            "exit_code" => "integer"
          },
          ports: {
            "out" => ["stdout", "stderr", "exit_code"],
            "error" => ["stderr", "exit_code"]
          }
        )
      }
    end
  end

  class Registry
    def self.default_dir
      File.join(Dir.home, ".config", "jawt", "nodes")
    end

    def self.user_nodes(dir = default_dir)
      return {} unless Dir.exist?(dir)

      Dir.glob(File.join(dir, "*", "node.toml")).each_with_object({}) do |path, acc|
        node = Node.from_toml(path)
        acc[node.name] = node
      end
    end

    attr_reader :nodes

    def initialize(nodes = {})
      @nodes = nodes.transform_keys(&:to_s)
    end

    def self.default
      new(Builtins.all.merge(user_nodes))
    end

    def fetch(name)
      @nodes[name.to_s]
    end

    def key?(name)
      @nodes.key?(name.to_s)
    end

    def names
      @nodes.keys.sort
    end
  end
end
