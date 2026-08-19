# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "jawt"
require "minitest/autorun"

module WorkflowHelpers
  def run_config
    <<~YAML
      shell: /bin/sh
      interactive: false
      login: false
    YAML
  end
end
