# frozen_string_literal: true

require_relative "test_helper"

class ConsoleTest < Minitest::Test
  def setup
    @console = Jawt::Console.new(nil)
  end

  def test_format_interval
    assert_equal "30s", @console.send(:format_interval, 30)
    assert_equal "5m", @console.send(:format_interval, 300)
    assert_equal "2h", @console.send(:format_interval, 7200)
    assert_equal "1d", @console.send(:format_interval, 86_400)
  end

  def test_format_due_in
    assert_equal "ahora", @console.send(:format_due_in, 0)
    assert_equal "45s", @console.send(:format_due_in, 45)
    assert_equal "3m 12s", @console.send(:format_due_in, 192)
    assert_equal "1h 5m", @console.send(:format_due_in, 3900)
  end

  def test_next_in_queue
    workflows = [
      { "name" => "a", "scheduled" => true, "valid" => true, "running" => false, "due_in" => 100 },
      { "name" => "b", "scheduled" => true, "valid" => true, "running" => false, "due_in" => 10 },
      { "name" => "c", "scheduled" => false, "valid" => true }
    ]
    assert_equal "b", @console.send(:next_in_queue, workflows)
  end

  def test_next_in_queue_skips_running_and_invalid
    workflows = [
      { "name" => "a", "scheduled" => true, "valid" => true, "running" => true, "due_in" => 5 },
      { "name" => "b", "scheduled" => true, "valid" => false, "running" => false, "due_in" => 5 }
    ]
    assert_nil @console.send(:next_in_queue, workflows)
  end
end
