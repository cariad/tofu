# shellcheck shell=bash
#
# A stand-in `gh` for the tests that write comments.
#
# Puts a stand-in `gh` in $TEST_TMPDIR/bin, for PR 18 of cariad/tofu. It
# answers with the real responses in tests/fixtures/github, which
# tests/fixtures/README.md lists, through the call's own `--jq` filter:
#
# - The PR: pull.json.
# - Its comments: STUB_COMMENTS (comments.json by default), and from the
#   second listing on, STUB_LATER_COMMENTS if it's set.
# - A new comment: STUB_CREATED (created-1.json by default).
# - Updating the comment updated.json is: updated.json. It has no answer for
#   updating any other.
# - A deleted comment: nothing, as `gh` prints.
#
# Logs each call's arguments to $TEST_TMPDIR/gh.log, any request body to
# $TEST_TMPDIR/gh.stdin, the GH_* settings it's given to $TEST_TMPDIR/gh.env,
# and what's left in the plan action's private directory, if there is one, to
# $TEST_TMPDIR/gh.saw.
#
# A call whose arguments contain FAIL_CALL fails instead. One whose arguments
# contain HANG_CALL writes its PID to $TEST_TMPDIR/gh.pid and takes a second.
stub_gh() {
  mkdir -p "$TEST_TMPDIR/bin"

  # A link, so the stand-in works from any directory.
  ln -sfn "$PWD/tests/fixtures/github" "$TEST_TMPDIR/github"

  # Each run of a script starts with its first listing.
  rm -f "$TEST_TMPDIR/gh.listed"

  cat >"$TEST_TMPDIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$TEST_TMPDIR/gh.log"
echo "GH_TOKEN=${GH_TOKEN-unset} GH_TELEMETRY=${GH_TELEMETRY-unset} GH_HOST=${GH_HOST-unset}" >"$TEST_TMPDIR/gh.env"
ls -A "$TEST_TMPDIR"/runner-temp/cariad-tofu.* >"$TEST_TMPDIR/gh.saw" 2>/dev/null
if [[ $* == *--input* ]]; then
  cat >"$TEST_TMPDIR/gh.stdin"
fi
if [[ -n ${HANG_CALL:-} && $* == *"$HANG_CALL"* ]]; then
  echo $$ >"$TEST_TMPDIR/gh.pid"
  sleep 1
fi
if [[ -n ${FAIL_CALL:-} && $* == *"$FAIL_CALL"* ]]; then
  echo "gh: the call failed" >&2
  exit 1
fi
cd "$TEST_TMPDIR/github"
case $* in
  *" repos/cariad/tofu/pulls/18 "*) response=pull.json ;;
  *--paginate*)
    response=${STUB_COMMENTS:-comments.json}
    [[ ! -e $TEST_TMPDIR/gh.listed ]] || response=${STUB_LATER_COMMENTS:-$response}
    touch "$TEST_TMPDIR/gh.listed"
    ;;
  *"--method POST "*) response=${STUB_CREATED:-created-1.json} ;;
  *"--method PATCH "*"/comments/$(jq .id updated.json) "*) response=updated.json ;;
  *"--method DELETE "*) exit 0 ;;
  *) echo "The stand-in gh has no answer for: $*" >&2; exit 1 ;;
esac
# A `--jq` filter is always the last argument. For the scripts' filters,
# `jq -r` prints exactly what `gh` does.
if [[ $* == *" --jq "* ]]; then
  jq -r "${!#}" "$response"
else
  cat "$response"
fi
EOF
  chmod +x "$TEST_TMPDIR/bin/gh"
}

# Prints the head commit of the PR the stand-in `gh` answers for.
pr_head() {
  jq -r .head.sha tests/fixtures/github/pull.json
}
