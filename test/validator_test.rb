# frozen_string_literal: true

require_relative "test_helper"

class ValidatorTest < Minitest::Test
  def setup
    @registry = Jawt::Registry.default
  end

  def test_valid_workflow
    result = validate(valid_yaml)
    assert result.ok?, result.errors.join("\n")
  end

  def test_unknown_node_type
    result = validate(<<~YAML)
      workflow:
        name: x
        nodes:
          start: { type: start }
          mistery: { type: nope }
          end: { type: end }
        edges: []
    YAML
    refute result.ok?
    assert result.errors.any? { |e| e.include?("tipo desconocido") }
  end

  def test_missing_start
    result = validate(<<~YAML)
      workflow:
        name: x
        nodes:
          a: { type: run, command: "echo" }
          end: { type: end }
        edges: []
    YAML
    refute result.ok?
    assert result.errors.any? { |e| e.include?("'start'") }
  end

  def test_missing_end
    result = validate(<<~YAML)
      workflow:
        name: x
        nodes:
          start: { type: start }
        edges: []
    YAML
    refute result.ok?
    assert result.errors.any? { |e| e.include?("'end'") }
  end

  def test_dangling_edge
    result = validate(<<~YAML)
      workflow:
        name: x
        nodes:
          start: { type: start }
          end: { type: end }
        edges:
          - from: start.out
            to: ghost.in
    YAML
    refute result.ok?
    assert result.errors.any? { |e| e.include?("inexistente") }
  end

  def test_cycle
    result = validate(<<~YAML)
      workflow:
        name: x
        nodes:
          start: { type: start }
          a: { type: run, command: "echo" }
          b: { type: run, command: "echo" }
          end: { type: end }
        edges:
          - from: start.out
            to: a.in
          - from: a.out
            to: b.in
          - from: b.out
            to: a.in
    YAML
    refute result.ok?
    assert result.errors.any? { |e| e.include?("ciclo") }
  end

  def test_required_input_missing
    result = validate(<<~YAML)
      workflow:
        name: x
        nodes:
          start: { type: start }
          run: { type: run }
          end: { type: end }
        edges:
          - from: start.out
            to: run.in
          - from: run.out
            to: end.in
    YAML
    refute result.ok?
    assert result.errors.any? { |e| e.include?("requiere el input 'command'") }
  end

  def test_requires_unavailable
    result = validate(<<~YAML)
      workflow:
        name: x
        requires: [github]
        nodes:
          start: { type: start }
          end: { type: end }
        edges: []
    YAML
    refute result.ok?
    assert result.errors.any? { |e| e.include?("capacidad requerida") }
  end

  def test_array_field_not_consumed_is_valid
    node = Jawt::Node.new(
      name: "mixed",
      outputs: { "count" => "integer", "list" => "array<string>" },
      ports: { "out" => ["count", "list"] }
    )
    registry = Jawt::Registry.new(Jawt::Builtins.all.merge("mixed" => node))
    result = Jawt::Validator.new(registry).validate(Jawt::Workflow.from_yaml(<<~YAML))
      workflow:
        name: x
        nodes:
          start: { type: start }
          m: { type: mixed }
          end: { type: end }
        edges:
          - from: start.out
            to: m.in
          - from: m.out
            to: end.in
    YAML
    assert result.ok?, result.errors.join("\n")
  end

  private

  def validate(yaml)
    Jawt::Validator.new(@registry).validate(Jawt::Workflow.from_yaml(yaml))
  end

  def valid_yaml
    <<~YAML
      workflow:
        name: deploy
        nodes:
          start: { type: start }
          git-diff:
            type: run
            command: "echo ok"
          check:
            type: condition
            when: "${git-diff.exit_code} == 0"
          tests:
            type: run
            command: "echo tests"
          notify:
            type: run
            command: "echo notify"
          end: { type: end }
        edges:
          - from: start.out
            to: git-diff.in
          - from: git-diff.out
            to: check.in
          - from: check.true
            to: tests.in
          - from: check.false
            to: notify.in
          - from: tests.out
            to: end.in
          - from: notify.out
            to: end.in
    YAML
  end
end
