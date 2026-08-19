# frozen_string_literal: true

require_relative "test_helper"

class ScheduleTest < Minitest::Test
  def test_parse_interval
    assert_equal 300, Jawt::Schedule.parse({ "every" => "5m" }).interval_seconds
    assert_equal 60, Jawt::Schedule.parse({ "every" => "1m" }).interval_seconds
    assert_equal 3600, Jawt::Schedule.parse({ "every" => "1h" }).interval_seconds
    assert_equal 10, Jawt::Schedule.parse({ "every" => "10s" }).interval_seconds
  end

  def test_parse_string
    schedule = Jawt::Schedule.parse("5m")
    assert schedule.interval?
    assert_equal 300, schedule.interval_seconds
  end

  def test_parse_nil
    assert_nil Jawt::Schedule.parse(nil)
    assert_nil Jawt::Schedule.parse({})
  end

  def test_workflow_reads_schedule
    workflow = Jawt::Workflow.from_yaml(<<~YAML)
      workflow:
        name: x
        schedule:
          every: 5m
        nodes:
          start: { type: start }
          end: { type: end }
        edges: []
    YAML

    assert workflow.schedule.interval?
    assert_equal 300, workflow.schedule.interval_seconds
  end

  def test_workflow_without_schedule
    workflow = Jawt::Workflow.from_yaml(<<~YAML)
      workflow:
        name: x
        nodes:
          start: { type: start }
          end: { type: end }
        edges: []
    YAML

    assert_nil workflow.schedule
  end
end
