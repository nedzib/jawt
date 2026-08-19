# frozen_string_literal: true

require_relative "test_helper"

class RunnerTest < Minitest::Test
  def setup
    @registry = Jawt::Registry.default
  end

  def test_linear_workflow_succeeds
    report = run_workflow(<<~YAML)
      workflow:
        name: test
        nodes:
          start: { type: start }
          hello:
            type: run
            command: "echo hello"
            shell: /bin/sh
            interactive: false
            login: false
          end: { type: end }
        edges:
          - from: start.out
            to: hello.in
          - from: hello.out
            to: end.in
    YAML

    assert report.success?
    assert_equal "hello\n", report.nodes["hello"].outputs["stdout"]
    assert_equal 0, report.nodes["hello"].outputs["exit_code"]
  end

  def test_condition_routes_to_true_branch
    report = run_workflow(<<~YAML)
      workflow:
        name: test
        nodes:
          start: { type: start }
          check:
            type: condition
            when: "1 == 1"
          yes-branch:
            type: run
            command: "echo yes"
            shell: /bin/sh
            interactive: false
            login: false
          no-branch:
            type: run
            command: "echo no"
            shell: /bin/sh
            interactive: false
            login: false
          end: { type: end }
        edges:
          - from: start.out
            to: check.in
          - from: check.true
            to: yes-branch.in
          - from: check.false
            to: no-branch.in
          - from: yes-branch.out
            to: end.in
          - from: no-branch.out
            to: end.in
    YAML

    assert_equal :success, report.nodes["yes-branch"].status
    assert_nil report.nodes["no-branch"]
  end

  def test_failure_stop_aborts
    report = run_workflow(<<~YAML)
      workflow:
        name: test
        nodes:
          start: { type: start }
          fail:
            type: run
            command: "exit 3"
            shell: /bin/sh
            interactive: false
            login: false
          after:
            type: run
            command: "echo after"
            shell: /bin/sh
            interactive: false
            login: false
          end: { type: end }
        edges:
          - from: start.out
            to: fail.in
          - from: fail.out
            to: after.in
          - from: after.out
            to: end.in
    YAML

    assert report.failed?
    assert_equal :failed, report.nodes["fail"].status
    assert_equal :skipped, report.nodes["after"].status
  end

  def test_failure_continue_routes_to_error_port
    report = run_workflow(<<~YAML)
      workflow:
        name: test
        nodes:
          start: { type: start }
          fail:
            type: run
            command: "exit 2"
            shell: /bin/sh
            interactive: false
            login: false
            on_failure: continue
          handler:
            type: run
            command: "echo handled"
            shell: /bin/sh
            interactive: false
            login: false
          end: { type: end }
        edges:
          - from: start.out
            to: fail.in
          - from: fail.error
            to: handler.in
          - from: fail.out
            to: end.in
          - from: handler.out
            to: end.in
    YAML

    assert_equal :failed, report.nodes["fail"].status
    assert_equal :success, report.nodes["handler"].status
    assert_includes report.nodes["handler"].outputs["stdout"], "handled"
  end

  def test_multiplex_fans_out
    report = run_workflow(<<~YAML)
      workflow:
        name: test
        nodes:
          start: { type: start }
          fan:
            type: multiplex
            items: [one, two, three]
          worker:
            type: run
            command: "echo hi"
            shell: /bin/sh
            interactive: false
            login: false
          end: { type: end }
        edges:
          - from: start.out
            to: fan.in
          - from: fan.out
            to: worker.in
          - from: worker.out
            to: end.in
    YAML

    fan = report.nodes["fan"]
    assert_equal %w[one two three], fan.outputs["items"]
    worker = report.nodes["worker"]
    assert_equal 3, worker.children.size
    assert_equal :success, worker.status
  end

  def test_config_values_resolve_templates
    report = run_workflow(<<~YAML)
      workflow:
        name: tpl
        nodes:
          start: { type: start }
          counter:
            type: run
            command: "echo 7"
            shell: /bin/sh
            interactive: false
            login: false
          echoer:
            type: run
            command: "echo count=${counter.exit_code}"
            shell: /bin/sh
            interactive: false
            login: false
          end: { type: end }
        edges:
          - from: start.out
            to: counter.in
          - from: counter.out
            to: echoer.in
          - from: echoer.out
            to: end.in
    YAML

    assert report.success?, report.nodes.map { |_, r| r.error }.compact.inspect
    assert_includes report.nodes["echoer"].outputs["stdout"], "count=0"
  end

  private

  def run_workflow(yaml)
    workflow = Jawt::Workflow.from_yaml(yaml)
    result = Jawt::Validator.new(@registry).validate(workflow)
    assert result.ok?, result.errors.join("\n")
    Jawt::Runner.new(registry: @registry).run(workflow)
  end
end
