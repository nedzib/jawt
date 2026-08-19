# frozen_string_literal: true

module Jawt
  class Type
    PRIMITIVES = %w[string integer float boolean object any].freeze

    attr_reader :name, :element

    def initialize(name, element = nil)
      @name = name
      @element = element
    end

    def self.parse(raw)
      return raw if raw.is_a?(Type)

      str = raw.to_s.strip
      if str =~ /\Aarray<(.+)>\z/
        new("array", parse(Regexp.last_match(1)))
      else
        new(str)
      end
    end

    def array?
      name == "array"
    end

    def to_s
      array? && element ? "array<#{element}>" : name
    end

    def assignable_from?(other)
      other = Type.parse(other) unless other.is_a?(Type)
      return true if name == "any" || other.name == "any"
      return true if name == "float" && other.name == "integer"
      return false unless name == other.name
      return true unless array?
      return true if element.nil? || other.element.nil?

      element.assignable_from?(other.element)
    end
  end
end
