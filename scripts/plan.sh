#!/usr/bin/env bash
#
# Plans a root module for a pull request, and writes the plan to the step's
# summary and to the root module's comment on the PR. It's the plan action's
# only step.
#
# Inputs, as environment variables:
#
# - WORKING_DIRECTORY: the action's `working-directory` input.
# - CARIAD_TOFU_GITHUB_TOKEN: the job's token, which only gh gets.
# - The runner's GITHUB_EVENT_NAME, GITHUB_EVENT_PATH, GITHUB_OUTPUT,
#   GITHUB_STEP_SUMMARY, GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_RUN_ID and
#   RUNNER_TEMP.
#
# Sets the step's `changes` output to `true` or `false`, unless the plan fails.
# The step fails if the plan fails or the comment can't be written.
#
# The plan file and the JSON plan hold secrets in plain text, so they're only
# written to a private directory under RUNNER_TEMP. They're deleted once the
# comment's body is rendered, and the directory when this script exits.
#
# The action runs this script with `exec`, so the runner's signals reach it when
# the job is cancelled or times out, and it stops tofu then too.
set -euo pipefail

# Everything this script and tofu write is private to the runner's user.
umask 077

# Usage: fail MESSAGE
fail() {
  echo "::error::$1" >&2
  exit 1
}

if [[ ${GITHUB_EVENT_NAME:-} != pull_request ]]; then
  fail "The plan action only runs on pull_request, not ${GITHUB_EVENT_NAME:-an unknown event}."
fi

command -v tofu >/dev/null || fail "tofu isn't on the PATH. Install OpenTofu before the plan action."
command -v gh >/dev/null || fail "gh isn't on the PATH. The plan action needs a GitHub-hosted Ubuntu runner."
command -v jq >/dev/null || fail "jq isn't on the PATH. The plan action needs a GitHub-hosted Ubuntu runner."

# jq 1.6 can't run render-comment.sh, which names a variable `$import`, and it
# rounds integers over 2^53, so plans that differ only in a big number would get
# the same fingerprint.
jq -ne '1 as $import | ("100000000000000001" | fromjson | tojson) == "100000000000000001"' >/dev/null 2>&1 ||
  fail "The runner's jq is too old. The plan action needs jq 1.7 or later."

sha=$(jq -r '.pull_request.head.sha // empty' "$GITHUB_EVENT_PATH")
[[ -n $sha ]] || fail "The pull_request event has no head commit."

pr=$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH")
[[ -n $pr ]] || fail "The pull_request event has no PR number."

# A leading `./` and any trailing `/` are removed, so `./infra/` and `infra` are
# the same root module. The ranges are ASCII-only in every locale, because
# bash 5 turns on `globasciiranges` by default.
dir=${WORKING_DIRECTORY:-}
dir=${dir#./}

while [[ $dir == */ ]]; do dir=${dir%/}; done

if [[ -z $dir || $dir == *[!A-Za-z0-9._/-]* ]]; then
  fail "working-directory must be a directory whose name has only A-Z, a-z, 0-9, ., _, / and -."
fi

# One root module must always have the same `dir`, inside the workspace, so
# only a lone `.` may be a `.` part, and there are no empty or `..` parts.
if [[ $dir != . && ( $dir == /* || /$dir/ == *//* || /$dir/ == */./* || /$dir/ == */../* ) ]]; then
  fail "working-directory must be a path inside the workspace, such as infra/blog, without empty, . or .. parts."
fi

[[ -d $dir ]] || fail "working-directory $dir isn't a directory."

# A symlink could still lead outside the workspace, so compare where both
# really are.
real=$(cd "$dir" && pwd -P)

workspace=$(pwd -P)

[[ $real == "$workspace" || $real == "$workspace"/* ]] ||
  fail "working-directory $dir is outside the workspace."

export TF_IN_AUTOMATION=1 TF_INPUT=0

# TF_LOG output can include secrets, such as request bodies, so it's never
# printed.
unset "${!TF_LOG@}"

# The job's token is given only to gh, so tofu and its providers can't pick it
# up by accident: as GH_TOKEN, GitHub's provider would quietly use it, through
# `gh auth token`. A process that looks for it could still read it from this
# script's starting environment.
[[ -n ${CARIAD_TOFU_GITHUB_TOKEN:-} ]] ||
  fail "The plan action has no GitHub token. Its step sets CARIAD_TOFU_GITHUB_TOKEN from github.token."
github_token=$CARIAD_TOFU_GITHUB_TOKEN
unset CARIAD_TOFU_GITHUB_TOKEN

tofu version

run_url=$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID

tmp=$(mktemp -d "${RUNNER_TEMP:?}/cariad-tofu.XXXXXX")

trap 'rm -rf -- "$tmp"' EXIT

# When the job is cancelled or times out, the runner sends this script SIGINT,
# then SIGTERM. Bash only acts on a trapped signal straight away while it's in
# `wait`, so tofu runs in the background. The trap stops tofu and exits, which
# runs the EXIT trap.
child=
trap 'stop 130' INT
trap 'stop 143' TERM

# Stops tofu, giving it up to 5 seconds to finish, then exits with STATUS. The
# runner sends SIGTERM 7.5 seconds after SIGINT, so this ends first.
#
# Usage: stop STATUS
stop() {
  if [[ -n $child ]]; then
    kill "$child" 2>/dev/null || true
    for _ in {1..50}; do
      kill -0 "$child" 2>/dev/null || break
      sleep 0.1
    done
  fi

  exit "$1"
}

# Usage: wait_for COMMAND [ARG...]
wait_for() {
  "$@" &
  child=$!
  wait "$child"
}

# Runs init, plan and show. Returns 0 if the plan has no changes, 2 if it has
# some, and 1 if any of them fails. `set -e` doesn't apply in a function whose
# status is tested, hence each `|| return 1`.
run_tofu() {
  local status=0
  wait_for tofu -chdir="$dir" init -input=false -lockfile=readonly || return 1
  wait_for tofu -chdir="$dir" plan -input=false -lock=false -no-color -detailed-exitcode -out="$tmp/plan" || status=$?
  ((status == 0 || status == 2)) || return 1
  wait_for tofu -chdir="$dir" show -no-color "$tmp/plan" >"$tmp/plan.txt" || return 1
  wait_for tofu -chdir="$dir" show -json "$tmp/plan" >"$tmp/plan.json" || return 1
  return "$status"
}

# Lines in tofu's output could otherwise act as workflow commands, such as
# `::set-output`, so the runner ignores them until it sees a random token.
token=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
echo "::stop-commands::$token"
result=0
run_tofu || result=$?
# tofu has finished, so there's nothing left for `stop` to stop.
child=
echo "::$token::"

if ((result == 1)); then status=plan-failed; else status=planned; fi

DIR=$dir STATUS=$status SHA=$sha RUN_URL=$run_url PLAN_TEXT=$tmp/plan.txt PLAN_JSON=$tmp/plan.json \
  bash "$(dirname "$0")/render-comment.sh" >"$tmp/body.md"

# Only the body is needed from here, so delete the rest now. A cancellation
# waits for gh (below), and if the runner kills this script before gh
# finishes, the EXIT trap never runs.
rm -f -- "$tmp/plan" "$tmp/plan.json" "$tmp/plan.txt"

cat "$tmp/body.md" >>"$GITHUB_STEP_SUMMARY"

if ((result == 2)); then
  echo "changes=true" >>"$GITHUB_OUTPUT"
elif ((result == 0)); then
  echo "changes=false" >>"$GITHUB_OUTPUT"
fi

# Before the comment, so a failed write doesn't hide it.
if ((result == 1)); then
  echo "::error::The plan for $dir failed. tofu's output above says why." >&2
fi

# After the summary and the output, so they're still there if this fails. gh
# runs in the foreground, so a cancellation waits for the whole write,
# including its clean-up after a race. There's no URL if the PR has moved on,
# because the newer commit's run writes the comment.
#
# gh gets none of the consumer's GH_* settings, such as GH_HOST or GH_DEBUG,
# though tofu still does.
url=$(
  unset "${!GH_@}"
  GH_TOKEN=$github_token GH_TELEMETRY=false REPO=$GITHUB_REPOSITORY PR=$pr DIR=$dir HEAD_SHA=$sha \
    BODY=$tmp/body.md bash "$(dirname "$0")/write-comment.sh"
) || fail "Couldn't write the plan comment for $dir. The error above says why."

[[ -z $url ]] || echo "The plan comment for $dir is at $url"

((result != 1)) || exit 1
