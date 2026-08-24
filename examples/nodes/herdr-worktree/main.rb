#!/usr/bin/env ruby
require "json"
require "open3"

def sh(*args)
  Open3.capture3(*args)
end

begin
  inputs = JSON.parse($stdin.read)
rescue JSON::ParserError
  inputs = {}
end

item = inputs["item"].is_a?(Hash) ? inputs["item"] : {}
cwd  = (inputs["cwd"] || "").to_s.strip
number = item["number"]
branch = (inputs["branch"] || item["branch"] || "").to_s.strip
author = item["author"].to_s.strip
name = (author.empty? || number.nil?) ? nil : "#{author}_#{number}"

if branch.empty? || cwd.empty?
  puts JSON.generate(item.merge("action" => "error", "message" => "faltan 'cwd' o 'branch'"))
  exit 0
end

list_out, _, list_status = sh("herdr", "--session", "default", "worktree", "list", "--cwd", cwd)
unless list_status.success?
  puts JSON.generate(item.merge("action" => "error", "message" => "worktree list falló"))
  exit 0
end

begin
  worktrees = JSON.parse(list_out).dig("result", "worktrees") || []
rescue JSON::ParserError
  worktrees = []
end

existing = worktrees.find { |wt| wt["branch"] == branch }

if existing && existing["open_workspace_id"].to_s.strip != ""
  puts JSON.generate(item.merge(
    "action" => "skipped",
    "branch" => branch,
    "workspace_id" => existing["open_workspace_id"],
    "message" => "ya estaba abierto"
  ))
  exit 0
end

if existing
  action = "opened"
  out, err, status = sh("herdr", "--session", "default", "worktree", "open",
                        "--cwd", cwd, "--branch", branch, "--no-focus")
else
  action = "created"
  if number
    _, _, rev_status = sh("git", "-C", cwd, "rev-parse", "--verify", "--quiet", "refs/heads/#{branch}")
    unless rev_status.success?
      _, fetch_err, fetch_status = sh("git", "-C", cwd, "fetch", "origin", "pull/#{number}/head:refs/heads/#{branch}")
      unless fetch_status.success?
        puts JSON.generate(item.merge("action" => "error", "message" => "no se pudo traer la rama: #{fetch_err.strip}"))
        exit 0
      end
    end
  end

  args = ["herdr", "--session", "default", "worktree", "create",
          "--cwd", cwd, "--branch", branch, "--no-focus"]
  args += ["--path", File.join(cwd, name)] if name
  out, err, status = sh(*args)
end

unless status.success?
  puts JSON.generate(item.merge("action" => "error", "message" => "worktree #{action} falló: #{err.strip}"))
  exit 0
end

begin
  created = JSON.parse(out).dig("result")
  pane_id = created.dig("root_pane", "pane_id")
  workspace_id = created.dig("workspace", "workspace_id")
rescue JSON::ParserError
  puts JSON.generate(item.merge("action" => "error", "message" => "respuesta inválida del worktree"))
  exit 0
end

puts JSON.generate(item.merge(
  "action" => action,
  "branch" => branch,
  "name" => name,
  "workspace_id" => workspace_id,
  "pane_id" => pane_id,
  "message" => "worktree #{action}: #{branch}"
))
