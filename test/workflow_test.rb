# frozen_string_literal: true

require_relative "test_helper"

class WorkflowTest < Minitest::Test
  def test_from_yaml_parses_nodes
    wf = Jawt::Workflow.from_yaml(valid_yaml)
    assert_equal "deploy", wf.name
    assert_equal %w[start git-diff check tests notify end], wf.nodes.keys
    assert_equal "run", wf.node("git-diff").type
    assert_equal "echo ok", wf.node("git-diff").config["command"]
  end

  def test_from_yaml_parses_edges_with_default_ports
    wf = Jawt::Workflow.from_yaml(valid_yaml)
    first = wf.edges.find { |e| e.from.node == "check" && e.from.port == "true" }
    refute_nil first
    assert_equal "tests", first.to.node
    assert_equal "in", first.to.port
  end

  def test_requires
    wf = Jawt::Workflow.from_yaml(<<~YAML)
      workflow:
        name: x
        requires: [run, condition]
        nodes:
          start: { type: start }
          end: { type: end }
        edges: []
    YAML
    assert_equal %w[run condition], wf.requires
  end

  def test_missing_type_raises
    assert_raises(Jawt::Error) do
      Jawt::Workflow.from_yaml(<<~YAML)
        workflow:
          name: x
          nodes:
            start: { type: start }
            ghost: {}
          edges: []
      YAML
    end
  end

  private

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
