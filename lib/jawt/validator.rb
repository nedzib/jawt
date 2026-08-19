# frozen_string_literal: true

module Jawt
  class Validator
    Result = Struct.new(:valid, :errors, keyword_init: true) do
      def ok?
        valid
      end
    end

    def initialize(registry)
      @registry = registry
    end

    def validate(workflow)
      errors = []
      errors.concat(check_node_types(workflow))
      errors.concat(check_requires(workflow))
      errors.concat(check_terminals(workflow))
      errors.concat(check_edges(workflow))
      errors.concat(check_cycles(workflow))
      errors.concat(check_inputs(workflow))
      errors.concat(check_cardinality(workflow))
      Result.new(valid: errors.empty?, errors: errors)
    end

    private

    def check_node_types(workflow)
      workflow.nodes.values.filter_map do |spec|
        next if @registry.key?(spec.type)

        "nodo '#{spec.id}' usa un tipo desconocido '#{spec.type}'"
      end
    end

    def check_requires(workflow)
      workflow.requires.filter_map do |req|
        next if @registry.key?(req)

        "capacidad requerida '#{req}' no está disponible"
      end
    end

    def check_terminals(workflow)
      errors = []
      starts = workflow.start_nodes.size
      ends = workflow.end_nodes.size
      errors << "el workflow debe tener exactamente un nodo 'start' (tiene #{starts})" unless starts == 1
      errors << "el workflow debe tener al menos un nodo 'end' (tiene #{ends})" if ends < 1
      errors
    end

    def check_edges(workflow)
      workflow.edges.flat_map do |edge|
        errors = []
        unless workflow.node(edge.from.node)
          errors << "conexión '#{edge.from.node}.#{edge.from.port} -> #{edge.to.node}.#{edge.to.port}' referencia un nodo inexistente '#{edge.from.node}'"
          next errors
        end
        unless workflow.node(edge.to.node)
          errors << "conexión '#{edge.from.node}.#{edge.from.port} -> #{edge.to.node}.#{edge.to.port}' referencia un nodo inexistente '#{edge.to.node}'"
          next errors
        end

        from_node = @registry.fetch(workflow.node(edge.from.node).type)
        to_node = @registry.fetch(workflow.node(edge.to.node).type)

        errors << "nodo '#{edge.from.node}' no tiene el puerto '#{edge.from.port}'" unless from_node.port?(edge.from.port)
        errors << "el nodo '#{edge.to.node}' no acepta entradas (es un 'start')" if workflow.node(edge.to.node).type == "start"
        errors << "nodo '#{edge.to.node}' no tiene el puerto '#{edge.to.port}'" unless edge.to.port == Workflow::DEFAULT_TO_PORT || to_node.port?(edge.to.port)

        check_type_compatibility(workflow, edge, from_node, to_node, errors)
        errors
      end
    end

    def check_type_compatibility(workflow, edge, from_node, to_node, errors)
      emitted = emitted_fields(workflow, edge)
      emitted.each do |field, type|
        input = to_node.input(field)
        next unless input
        next if input[:type].assignable_from?(type)

        errors << "tipo incompatible en '#{edge.from.node}.#{edge.from.port} -> #{edge.to.node}.#{edge.to.port}': '#{type}' no es asignable a '#{input[:type]}' (#{field})"
      end
    end

    def check_cycles(workflow)
      indegree = workflow.nodes.keys.to_h { |id| [id, 0] }
      adjacency = workflow.nodes.keys.to_h { |id| [id, []] }
      workflow.edges.each do |edge|
        next unless workflow.node(edge.from.node) && workflow.node(edge.to.node)

        adjacency[edge.from.node] << edge.to.node
        indegree[edge.to.node] += 1
      end

      queue = indegree.select { |_, d| d.zero? }.map(&:first)
      visited = 0
      until queue.empty?
        n = queue.shift
        visited += 1
        adjacency[n].each do |m|
          indegree[m] -= 1
          queue << m if indegree[m].zero?
        end
      end

      return [] if visited == workflow.nodes.size

      cyclic = indegree.select { |_, d| d.positive? }.keys
      ["el workflow contiene un ciclo en: #{cyclic.join(', ')}"]
    end

    def check_inputs(workflow)
      workflow.nodes.values.flat_map do |spec|
        node = @registry.fetch(spec.type)
        next [] unless node

        node.inputs.filter_map do |name, input|
          next unless input[:required]

          provided_by_config = spec.config.key?(name) || spec.config.key?(name.to_sym)
          feeding = workflow.incoming_edges(spec.id).select do |edge|
            emitted_fields(workflow, edge).key?(name)
          end

          if !provided_by_config && feeding.empty?
            "nodo '#{spec.id}' requiere el input '#{name}' y no está conectado ni definido"
          else
            nil
          end
        end
      end
    end

    def check_cardinality(workflow)
      workflow.edges.filter_map do |edge|
        spec = workflow.node(edge.from.node)
        next unless spec

        from_node = @registry.fetch(spec.type)
        next unless from_node

        to_spec = workflow.node(edge.to.node)
        next unless to_spec

        to_node = @registry.fetch(to_spec.type)
        next unless to_node

        array_fields = from_node.port_outputs(edge.from.port).select do |field|
          from_node.output_type(field)&.array? && to_node.input(field)
        end
        next if array_fields.empty?
        next if to_node.name == "multiplex" || to_node.cardinality == "array"

        "el puerto '#{edge.from.node}.#{edge.from.port}' emite un array ('#{array_fields.join(', ')}') pero '#{edge.to.node}' no es multiplex ni array"
      end
    end

    def emitted_fields(workflow, edge)
      spec = workflow.node(edge.from.node)
      return {} unless spec

      node = @registry.fetch(spec.type)
      return {} unless node

      node.port_outputs(edge.from.port).each_with_object({}) do |field, acc|
        acc[field] = node.output_type(field) if node.output_type(field)
      end
    end
  end
end
