#!/usr/bin/env ruby
require "json"
require "open3"

def capture(*args)
  out, err, status = Open3.capture3(*args)
  [out, err, status]
end

def infer_repo
  out, _, status = capture("git", "config", "--get", "remote.origin.url")
  return nil unless status.exitstatus.zero?

  url = out.strip
  return nil if url.empty?

  url =~ %r{[:/]([^/:]+/[^/]+?)(?:\.git)?$} ? Regexp.last_match(1) : nil
end

repo = ENV["JAWT_INPUT_REPO"].to_s.strip
repo = infer_repo if repo.empty?

if repo.nil? || repo.empty?
  warn "no se pudo determinar el repositorio (pasa 'repo' en el workflow)"
  exit 1
end

login_out, = capture("gh", "api", "user", "--jq", ".login")
login = login_out.strip

out, err, status = capture(
  "gh", "pr", "list", "--repo", repo,
  "--search", "review-requested:@me is:open",
  "--json", "number,title,url,headRefName,author"
)
if status.exitstatus != 0
  warn err
  exit status.exitstatus
end

candidates = out.to_s.empty? ? [] : JSON.parse(out)

items = candidates.filter_map do |pr|
  number = pr["number"]

  reviewers_out, _, rstatus = capture(
    "gh", "api", "repos/#{repo}/pulls/#{number}",
    "--jq", "[.requested_reviewers[].login]"
  )
  next unless rstatus.exitstatus.zero?

  reviewers = reviewers_out.to_s.empty? ? [] : JSON.parse(reviewers_out)
  next unless reviewers.include?(login)

  {
    "number" => number,
    "title" => pr["title"],
    "url" => pr["url"],
    "branch" => pr["headRefName"],
    "author" => pr.dig("author", "login")
  }
end

puts JSON.generate("count" => items.length, "items" => items)
