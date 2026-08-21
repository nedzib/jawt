#!/usr/bin/env ruby
require "json"
require "open3"

out, err, status = Open3.capture3(
  "gh", "pr", "list", "--author", "@me", "--state", "open",
  "--json", "number,title,url"
)

if status.exitstatus != 0
  warn err
  exit status.exitstatus
end

prs = out.to_s.empty? ? [] : JSON.parse(out)
puts JSON.generate("count" => prs.length, "prs" => prs)
