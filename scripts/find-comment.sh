#!/usr/bin/env bash
#
# Prints a root module's plan comment, as compact JSON, from a PR's comments.
# Prints nothing if it hasn't got one.
#
# Inputs:
#
# - DIR, an environment variable: the root module's directory, already checked
#   and tidied.
# - Standard input: the PR's issue comments, as `gh api --paginate` prints them.
#   That's one array when piped, but its help says each page is a separate
#   array, so both are read.
#
# Only comments the bot wrote count, and only if their first line is a marker
# for DIR. If several are, the oldest counts, so every run picks the same one.
set -euo pipefail

jq -c -s --arg dir "$DIR" '
  add // []
  | [
      .[]
      | select(.user.login == "github-actions[bot]" and .user.type == "Bot")
      | select(
          (.body // "") | split("\n")[0]
          | capture("^<!-- cariad/tofu (?<json>.*) -->$").json
          | (fromjson? // null) | .dir? == $dir
        )
    ]
  | min_by(.id) // empty'
