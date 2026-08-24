# frozen_string_literal: true

require "yaml"

module Jawt
  class Workflow
    PortRef = Struct.new(:node, :port, keyword_init: true)
    NodeSpec = Struct.new(:id, :type, :config, :label, keyword_init: true)
    Edge = Struct.new(:from, :to, keyword_init: true)

    DEFAULT_FROM_PORT = "out"
    DEFAULT_TO_PORT = "in"

    attr_reader :name, :description, :requires, :nodes, :edges, :schedule

    def initialize(name:, description: "", requires: [], nodes: {}, edges: [],
                   schedule: nil)
      @name = name.to_s
      @description = description.to_s
      @requires = Array(requires).map(&:to_s)
      @nodes = nodes
      @edges = edges
      @schedule = schedule
    end

    def node(id)
      nodes[id.to_s]
    end

    def label(id)
      spec = node(id)
      return id.to_s unless spec

      spec.label.to_s.empty? ? spec.id : spec.label.to_s
    end

    def start_nodes
      nodes.values.select { |n| n.type == "start" }
    end

    def end_nodes
      nodes.values.select { |n| n.type == "end" }
    end

    def incoming_edges(id)
      edges.select { |e| e.to.node == id.to_s }
    end

    def outgoing_edges(id)
      edges.select { |e| e.from.node == id.to_s }
    end

    def self.parse_ref(raw, default_port:)
      node, port = raw.to_s.split(".", 2)
      PortRef.new(node: node, port: port || default_port)
    end

    def self.from_yaml(source)
      data = YAML.safe_load(source, aliases: true)
      wf = data["workflow"] || data
      raise Error, "workflow inválido: falta la clave 'workflow'" unless wf.is_a?(Hash)

      nodes = (wf["nodes"] || {}).map do |id, spec|
        build_node_spec(id, spec)
      end.to_h { |n| [n.id, n] }

      edges = (wf["edges"] || []).map do |e|
        Edge.new(
          from: parse_ref(e["from"] || e[:from], default_port: DEFAULT_FROM_PORT),
          to: parse_ref(e["to"] || e[:to], default_port: DEFAULT_TO_PORT)
        )
      end

      new(
        name: wf["name"],
        description: wf["description"],
        requires: wf["requires"],
        nodes: nodes,
        edges: edges,
        schedule: Schedule.parse(wf["schedule"])
      )
    end

    def self.build_node_spec(id, spec)
      id = id.to_s
      spec = { "type" => spec } if spec.is_a?(String)
      spec ||= {}
      type = spec["type"] || spec[:type]
      raise Error, "nodo '#{id}' sin 'type'" if type.nil?

      config = spec.reject { |k, _| %w[type label].include?(k.to_s) }
      label = spec["label"] || spec[:label]
      NodeSpec.new(id: id, type: type.to_s, config: config, label: label&.to_s)
    end
  end
end
