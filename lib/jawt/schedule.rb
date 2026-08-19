# frozen_string_literal: true

module Jawt
  class Schedule
    UNITS = { "s" => 1, "m" => 60, "h" => 3600, "d" => 86_400 }.freeze

    attr_reader :interval_seconds, :cron

    def self.parse(raw)
      return nil if raw.nil?
      raw = { "every" => raw } if raw.is_a?(String)
      return nil unless raw.is_a?(Hash)
      return nil if raw.values_at("every", :every, "cron", :cron).compact.empty?

      new(raw)
    end

    def initialize(raw)
      @cron = raw["cron"] || raw[:cron]
      @interval_seconds = parse_interval(raw["every"] || raw[:every])
    end

    def scheduled?
      !interval_seconds.nil? || !cron.nil?
    end

    def interval?
      !interval_seconds.nil?
    end

    private

    def parse_interval(str)
      return nil if str.nil?

      match = str.to_s.strip.match(/\A(\d+)\s*(s|m|h|d)?\z/)
      return nil unless match

      match[1].to_i * UNITS.fetch(match[2] || "s")
    end
  end
end
