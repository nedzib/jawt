#!/usr/bin/env ruby
require "json"
require "open3"

assignee = ENV["JAWT_INPUT_ASSIGNEE"].to_s.empty? ? "@me" : ENV["JAWT_INPUT_ASSIGNEE"]

out, err, status = Open3.capture3(
  "gh", "pr", "list", "--assignee", assignee,
  "--json", "number,title,url"
)

if status.exitstatus != 0
  warn err
  exit status.exitstatus
end

prs = out.to_s.empty? ? [] : JSON.parse(out)
puts JSON.generate("count" => prs.length, "prs" => prs)
