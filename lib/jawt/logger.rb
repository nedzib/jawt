# frozen_string_literal: true

module Jawt
  class Logger
    attr_reader :entries

    def initialize(stream: $stdout, quiet: false)
      @stream = stream
      @quiet = quiet
      @entries = []
    end

    def log(id, message)
      @entries << "[#{id}] #{message}"
      @stream.puts "  #{id}: #{message}" unless @quiet
    end
  end
end
