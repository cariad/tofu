#!/usr/bin/env bash
#
# Creates or updates a root module's plan comment on a PR, and prints its URL.
#
# Inputs, as environment variables:
#
# - REPO: the repository, as OWNER/NAME.
# - PR: the pull request's number.
# - DIR: the root module's directory, already checked and tidied.
# - HEAD_SHA: the PR head commit this run planned.
# - BODY: a file holding the comment's body, from render-comment.sh.
#
# A re-run plans its original commit, so if the PR has moved on since, this
# writes nothing and leaves the comment to the newer run.
#
# Two runs can't race to write, because consumers run plans in a per-PR
# concurrency group that cancels the older run.
set -euo pipefail

# An empty HEAD_SHA would make every run skip writing, so refuse empty inputs.
: "${REPO:?}" "${PR:?}" "${DIR:?}" "${HEAD_SHA:?}" "${BODY:?}"

# The body's marker must be for DIR, or the next run wouldn't find this
# comment. find-comment.sh checks it, as if the bot had already written it.
jq -n --rawfile body "$BODY" '[{id: 0, user: {login: "github-actions[bot]", type: "Bot"}, body: $body}]' |
  bash "$(dirname "$0")/find-comment.sh" | grep -q . ||
  { echo "BODY's marker isn't for $DIR." >&2; exit 1; }

current=$(gh api "repos/$REPO/pulls/$PR" --jq .head.sha)
if [[ $current != "$HEAD_SHA" ]]; then
  echo "::notice::Not writing the plan comment, because the PR has moved on from $HEAD_SHA to $current." >&2
  exit 0
fi

existing=$(gh api --paginate "repos/$REPO/issues/$PR/comments?per_page=100" | bash "$(dirname "$0")/find-comment.sh")

# Sends the body as JSON on standard input, so it arrives exactly as written,
# and prints the comment's URL.
#
# Usage: send METHOD ENDPOINT
send() {
  jq -n --rawfile body "$BODY" '{body: $body}' | gh api --method "$1" "$2" --input - --jq .html_url
}

if [[ -n $existing ]]; then
  send PATCH "repos/$REPO/issues/comments/$(jq -r .id <<<"$existing")"
else
  send POST "repos/$REPO/issues/$PR/comments"
fi
