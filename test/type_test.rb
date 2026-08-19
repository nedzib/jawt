# frozen_string_literal: true

require_relative "test_helper"

class TypeTest < Minitest::Test
  def test_parse_array
    type = Jawt::Type.parse("array<string>")
    assert type.array?
    assert_equal "string", type.element.name
  end

  def test_parse_primitive
    assert_equal "string", Jawt::Type.parse("string").name
    refute Jawt::Type.parse("string").array?
  end

  def test_assignable
    assert Jawt::Type.parse("float").assignable_from?(Jawt::Type.parse("integer"))
    assert Jawt::Type.parse("any").assignable_from?(Jawt::Type.parse("string"))
    assert Jawt::Type.parse("string").assignable_from?(Jawt::Type.parse("string"))
    assert Jawt::Type.parse("array<string>").assignable_from?(Jawt::Type.parse("array<string>"))
  end

  def test_not_assignable
    refute Jawt::Type.parse("integer").assignable_from?(Jawt::Type.parse("string"))
    refute Jawt::Type.parse("array<string>").assignable_from?(Jawt::Type.parse("array<integer>"))
  end
end
