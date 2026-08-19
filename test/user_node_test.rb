# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class UserNodeTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("jawt-nodes")
    @nodes_dir = File.join(@dir, "nodes")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_user_node_executes_main_sh
    create_node("greeter", <<~TOML, <<~SH)
      name = "greeter"
      description = "Saluda"

      [inputs]
      name = { type = "string", required = true }

      [outputs]
      greeting = "string"

      [ports]
      out = ["greeting"]

      [behavior]
      cardinality = "single"
      on_failure = "stop"
    TOML
      #!/bin/sh
      echo "{\\"greeting\\":\\"hola $JAWT_INPUT_NAME\\"}"
    SH

    report = run_workflow(<<~YAML)
      workflow:
        name: greet
        nodes:
          start: { type: start }
          hi:
            type: greeter
            name: mundo
          end: { type: end }
        edges:
          - from: start.out
            to: hi.in
          - from: hi.out
            to: end.in
    YAML

    assert report.success?, report.nodes.map { |_, r| r.error }.compact.inspect
    assert_equal "hola mundo", report.nodes["hi"].outputs["greeting"]
  end

  def test_user_node_with_single_output_uses_raw_stdout
    create_node("upper", <<~TOML, <<~SH)
      name = "upper"
      description = "Mayúsculas"

      [inputs]
      text = { type = "string", required = true }

      [outputs]
      result = "string"

      [ports]
      out = ["result"]

      [behavior]
      on_failure = "stop"
    TOML
      #!/bin/sh
      printf '%s' "$JAWT_INPUT_TEXT" | tr a-z A-Z
    SH

    report = run_workflow(<<~YAML)
      workflow:
        name: up
        nodes:
          start: { type: start }
          up:
            type: upper
            text: "hola"
          end: { type: end }
        edges:
          - from: start.out
            to: up.in
          - from: up.out
            to: end.in
    YAML

    assert report.success?
    assert_equal "HOLA", report.nodes["up"].outputs["result"]
  end

  private

  def create_node(name, manifest, script)
    node_dir = File.join(@nodes_dir, name)
    FileUtils.mkdir_p(node_dir)
    File.write(File.join(node_dir, "node.toml"), manifest)
    File.write(File.join(node_dir, "main.sh"), script)
    File.chmod(0o755, File.join(node_dir, "main.sh"))
  end

  def run_workflow(yaml)
    workflow = Jawt::Workflow.from_yaml(yaml)
    registry = Jawt::Registry.new(
      Jawt::Builtins.all.merge(Jawt::Registry.user_nodes(@nodes_dir))
    )
    result = Jawt::Validator.new(registry).validate(workflow)
    assert result.ok?, result.errors.join("\n")
    Jawt::Runner.new(registry: registry).run(workflow)
  end
end
