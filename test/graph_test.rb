# frozen_string_literal: true

require_relative "test_helper"

class GraphTest < Minitest::Test
  def test_render_contains_nodes
    graph = Jawt::Graph.new(Jawt::Workflow.from_yaml(valid_yaml)).render
    assert_includes graph, "start"
    assert_includes graph, "check"
    assert_includes graph, "end"
  end

  def test_render_contains_boxes
    graph = Jawt::Graph.new(Jawt::Workflow.from_yaml(valid_yaml)).render
    assert_includes graph, "┌"
    assert_includes graph, "└"
  end

  private

  def valid_yaml
    <<~YAML
      workflow:
        name: deploy
        nodes:
          start: { type: start }
          check:
            type: condition
            when: "true"
          tests:
            type: run
            command: "echo tests"
          notify:
            type: run
            command: "echo notify"
          end: { type: end }
        edges:
          - from: start.out
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
