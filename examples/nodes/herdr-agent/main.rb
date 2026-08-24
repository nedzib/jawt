#!/usr/bin/env ruby
require "json"
require "open3"

def sh(*args)
  Open3.capture3(*args)
end

def error_code(err)
  JSON.parse(err.to_s.strip)["error"]["code"]
rescue JSON::ParserError, NoMethodError, TypeError
  nil
end

def start_agent(name, kind, pane_id)
  last_err = ""
  6.times do |i|
    sleep 2 if i.positive?

    out, err, status = sh("herdr", "agent", "start", name, "--kind", kind, "--pane", pane_id)
    return [:ok, out] if status.success?

    last_err = err
    return [:error, err] unless error_code(err) == "agent_pane_busy"
  end
  [:error, last_err]
end

begin
  inputs = JSON.parse($stdin.read)
rescue JSON::ParserError
  inputs = {}
end

item = inputs["item"].is_a?(Hash) ? inputs["item"] : {}
pane_id = (inputs["pane_id"] || item["pane_id"] || "").to_s.strip
kind = (inputs["kind"] || "").to_s.strip
kind = "claude" if kind.empty?
number = item["number"]
branch = item["branch"].to_s

if pane_id.empty?
  puts JSON.generate(item.merge("status" => "skipped"))
  exit 0
end

name = (inputs["name"] || "review-#{number}").to_s.strip

prompt = (inputs["prompt"] || "").to_s.strip
if prompt.empty?
  prompt = "Revisa el PR ##{number} de la rama `#{branch}`. " \
           "Compara la rama contra la principal y reporta hallazgos accionables."
end
prompt = prompt.gsub("{number}", number.to_s)
               .gsub("{branch}", branch)
               .gsub("{url}", item["url"].to_s)
               .gsub("{title}", item["title"].to_s)

result, payload = start_agent(name, kind, pane_id)
if result == :ok
  sh("herdr", "agent", "prompt", name, prompt)
  puts JSON.generate(item.merge("agent" => name, "status" => "started"))
else
  puts JSON.generate(item.merge("agent" => nil, "status" => "error", "error" => payload.to_s.strip))
end
