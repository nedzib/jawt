#!/usr/bin/env ruby
require "json"
require "open3"

begin
  inputs = JSON.parse($stdin.read)
rescue JSON::ParserError
  inputs = {}
end

item = inputs["item"].is_a?(Hash) ? inputs["item"] : {}
title = (inputs["title"] || "").to_s.strip
message = (inputs["message"] || "").to_s.strip

if title.empty? || message.empty?
  if item["action"].to_s == "skipped" || item["message"].to_s.strip.empty?
    puts JSON.generate(item.merge("notified" => false))
    exit 0
  end
  title = "JAWT - PR ##{item['number']}" if title.empty?
  message = item["message"].to_s if message.empty?
end

Open3.capture3("osascript", "-e", "on run argv",
               "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
               "-e", "end run", title, message)

puts JSON.generate(item.merge("notified" => true))
