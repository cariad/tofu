#!/usr/bin/env bash
#
# Prints the body of a root module's plan comment.
#
# Inputs, as environment variables:
#
# - DIR:       the root module's directory, already checked and
#              tidied.
# - STATUS:    `planned` or `plan-failed`.
# - SHA:       the PR's head commit.
# - RUN_URL:   the workflow run's URL.
# - FP:        the plan's fingerprint, if it has one. Ignored when
#              the plan failed.
# - PLAN_TEXT: file holding the output of `tofu show -no-color`. Only read when
#              STATUS is `planned`.
# - PLAN_JSON: file holding the output of `tofu show -json`. Only read when
#              STATUS is `planned`.
#
# shellcheck disable=SC2016 # Backticks in these strings are Markdown.
set -euo pipefail

# Byte counts, not character counts, from bash and awk.
export LC_ALL=C

# GitHub's limit for a comment body. It counts characters, and a character is
# at least one byte, so a body within this many bytes always fits.
max_bytes=65536

# Prints the hidden marker line. Escaping `<` and `>` means no value can end
# the HTML comment early.
#
# Usage: marker [FP]
marker() {
  jq -nr --arg dir "$DIR" --arg status "$STATUS" --arg sha "$SHA" --arg fp "${1:-}" '
    {v: 1, dir: $dir, status: $status, sha: $sha}
    + (if $fp == "" then {} else {fp: $fp} end)
    | "<!-- cariad/tofu \(tojson | gsub("<"; "\\u003c") | gsub(">"; "\\u003e")) -->"'
}

# Prints the comment's heading.
heading() {
  printf '### OpenTofu plan for `%s`\n\n' "$DIR"
}

case $STATUS in
  planned) ;;
  plan-failed)
    marker
    heading
    printf '**The plan failed** at %s in [this run](%s).\n' "$SHA" "$RUN_URL"
    exit 0
    ;;
  *)
    echo "STATUS must be planned or plan-failed, not \"$STATUS\"." >&2
    exit 1
    ;;
esac

# Counts changes as OpenTofu's own `Plan:` line does: only managed resources,
# with a replacement as both an add and a destroy. Then adds moves and output
# changes, which that line leaves out. Like OpenTofu, it only says "No changes."
# when nothing at all changes, including data sources that will be read.
summary=$(jq -r '
  [.resource_changes[]? | select(.mode == "managed")] as $managed
  | def count(f): [$managed[] | select(f)] | length;
  count(.change.importing != null) as $import
  | count(.change.actions | any(. == "create")) as $add
  | count(.change.actions | any(. == "update")) as $change
  | count(.change.actions | any(. == "delete")) as $destroy
  | count(.change.actions | any(. == "forget")) as $forget
  | ([.resource_changes[]? | select(.previous_address != null)] | length) as $move
  | ([.resource_changes[]? | select(.change.actions == ["read"])] | length) as $read
  # OpenTofu lists an output only when its value changes, not just its
  # sensitivity.
  | ([.output_changes // {} | .[] | select(.before != .after or .after_unknown != false)] | length) as $outputs
  | if $import + $add + $change + $destroy + $forget + $move + $read + $outputs == 0 then
      "No changes."
    else
      [
        if $import > 0 then "\($import) to import" else empty end,
        "\($add) to add",
        "\($change) to change",
        "\($destroy) to destroy",
        if $forget > 0 then "\($forget) to forget" else empty end,
        if $move > 0 then "\($move) to move" else empty end,
        if $outputs == 1 then "1 output to change"
        elif $outputs > 1 then "\($outputs) outputs to change"
        else empty end
      ] | join(", ") + "."
    end' "$PLAN_JSON")

version=$(jq -r .terraform_version "$PLAN_JSON")

# A fence longer than any run of backticks in the plan, so the plan can't end
# the code block.
fence=$(awk '
  {
    line = $0
    while (match(line, /`+/)) {
      if (RLENGTH > longest) longest = RLENGTH
      line = substr(line, RSTART + RLENGTH)
    }
  }
  END {
    fence = "```"
    while (length(fence) <= longest) fence = fence "`"
    print fence
  }' "$PLAN_TEXT")

# Prints the body with as many whole lines of the plan as fit in BUDGET bytes,
# then NOTE if it isn't empty.
#
# Usage: body BUDGET NOTE
body() {
  marker "${FP:-}"
  heading
  printf '**%s** Planned at %s by OpenTofu %s in [this run](%s).\n\n' "$summary" "$SHA" "$version" "$RUN_URL"
  printf '<details><summary>Plan</summary>\n\n%stext\n' "$fence"
  awk -v budget="$1" '{ used += length($0) + 1; if (used > budget) exit; print }' "$PLAN_TEXT"
  printf '%s\n\n</details>\n' "$fence"
  if [[ -n $2 ]]; then
    printf '\n%s\n' "$2"
  fi
}

# The bytes left for the plan once everything else is in the body.
budget=$((max_bytes - $(body 0 '' | wc -c)))

# Counted as body counts them: each line, plus its newline.
plan_bytes=$(awk '{ used += length($0) + 1 } END { print used + 0 }' "$PLAN_TEXT")

if ((plan_bytes <= budget)); then
  body "$budget" ''
else
  note="The plan is too long for a comment, so it's cut short. See all of it in [this run]($RUN_URL)."
  # The note adds itself, a blank line and a newline.
  body $((budget - ${#note} - 2)) "$note"
fi
