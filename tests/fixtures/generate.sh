#!/usr/bin/env bash
#
# Plans every fixture with OpenTofu and writes the real output of
# `tofu show -no-color` and `tofu show -json` to its `plan.txt` and `plan.json`.
# Run it with `mise run generate-fixtures`.
#
# Each fixture is planned in a temporary copy, so no state, `.terraform/` or
# plan file is ever written here. A fixture with a `before/` is planned against
# the state from applying `before/` first.
set -euo pipefail

cd "$(dirname "$0")"

# Settings in your shell, such as TF_CLI_ARGS_show, TF_WORKSPACE or a missing
# TERRAFORM_CONFIG file, would change the outputs, so unset them all ("${!TF_@}"
# lists the names of every TF_* variable). Then set the two that the plan action
# will.
unset "${!TF_@}" "${!TOFU_@}" TERRAFORM_CONFIG
export TF_IN_AUTOMATION=1 TF_INPUT=0

# Empty until the first fixture, so the trap can run before then.
work=
trap 'rm -rf "$work"' EXIT

# Prints the `tofu plan -detailed-exitcode` status a fixture must give: 0 for no
# changes, 1 for an error and 2 for changes. Keep in sync with README.md.
expected_status() {
  case $1 in
    empty | unchanged) echo 0 ;;
    failing-precondition) echo 1 ;;
    *) echo 2 ;;
  esac
}

# Plans the copy in $work, checks the status, and writes the plan's text and
# JSON to FIXTURE/NAME.txt and FIXTURE/NAME.json.
#
# Usage: plan FIXTURE NAME
plan() {
  local status=0 want
  # `|| status=$?` keeps the expected 1 or 2 from stopping the script.
  tofu -chdir="$work" plan -input=false -lock=false -detailed-exitcode -out=plan.tfplan >/dev/null || status=$?

  want=$(expected_status "$1")
  if ((status != want)); then
    echo "$1: tofu plan exited $status, but it should exit $want." >&2
    exit 1
  fi

  tofu -chdir="$work" show -no-color plan.tfplan >"$1/$2.txt"
  tofu -chdir="$work" show -json plan.tfplan >"$1/$2.json"
}

for fixture in */; do
  fixture=${fixture%/}
  echo "Planning $fixture"
  work=$(mktemp -d)
  cp "$fixture"/*.tf "$work/"

  if [[ -d $fixture/before ]]; then
    mkdir "$work/before"
    cp "$fixture"/before/*.tf "$work/before/"
    tofu -chdir="$work/before" init -input=false >/dev/null
    tofu -chdir="$work/before" apply -input=false -auto-approve >/dev/null
    # The local backend keeps its state in ./terraform.tfstate.
    mv "$work/before/terraform.tfstate" "$work/"
  fi

  tofu -chdir="$work" init -input=false >/dev/null
  plan "$fixture" plan

  # A second plan of the same change, so the tests can check that two real
  # plans of it fingerprint the same.
  if [[ $fixture == mixed-changes ]]; then
    plan "$fixture" plan-2
  fi

  rm -rf "$work"
done

# The plan action truncates plan text to fit a PR comment, so `large` must be
# too big for one.
size=$(wc -c <large/plan.txt)
if ((size <= 65536)); then
  echo "large/plan.txt is only $((size)) bytes. Raise its count." >&2
  exit 1
fi
