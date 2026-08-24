#!/usr/bin/env ruby
require "json"
require "open3"

assignee = ENV["JAWT_INPUT_ASSIGNEE"].to_s.strip
assignee = "@me" if assignee.empty?
repo = ENV["JAWT_INPUT_REPO"].to_s.strip

args = ["gh", "pr", "list"]
args += ["--repo", repo] unless repo.empty?
args += ["--assignee", assignee, "--state", "open",
         "--json", "number,title,url,headRefName"]

out, err, status = Open3.capture3(*args)

if status.exitstatus != 0
  warn err
  exit status.exitstatus
end

prs = out.to_s.empty? ? [] : JSON.parse(out)
items = prs.map do |pr|
  {
    "number" => pr["number"],
    "title" => pr["title"],
    "url" => pr["url"],
    "branch" => pr["headRefName"]
  }
end

puts JSON.generate("count" => items.length, "items" => items)
