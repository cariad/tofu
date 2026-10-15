# shellcheck shell=bash
#
# A stand-in `gh` for the tests that write comments.
#
# Puts a stand-in `gh` in $TEST_TMPDIR/bin, for PR 7 of cariad/tofu, which has
# the comments captured from a real PR.
#
# Logs each call's arguments to $TEST_TMPDIR/gh.log, any request body to
# $TEST_TMPDIR/gh.stdin, the GH_* settings it's given to $TEST_TMPDIR/gh.env,
# and what's left in the plan action's private directory, if there is one, to
# $TEST_TMPDIR/gh.saw.
#
# Prints PR_HEAD (or `abc`) as the PR's head, and the captured comments as the
# listing, with $TEST_TMPDIR/gh.extra added after the first.
#
# A write prints the comment's ID and URL; a new comment's ID is 9000000001.
#
# A call whose arguments contain FAIL_CALL fails instead. One whose arguments
# contain HANG_CALL writes its PID to $TEST_TMPDIR/gh.pid and takes a second.
stub_gh() {
  mkdir -p "$TEST_TMPDIR/bin"
  # A copy, so the stand-in works from any directory.
  cp tests/fixtures/github/comments.json "$TEST_TMPDIR/gh.comments"
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
case $* in
  *" repos/cariad/tofu/pulls/7 "*) echo "${PR_HEAD:-abc}" ;;
  *--paginate*)
    if [[ -e $TEST_TMPDIR/gh.listed && -e $TEST_TMPDIR/gh.extra ]]; then
      jq -s add "$TEST_TMPDIR/gh.comments" "$TEST_TMPDIR/gh.extra"
    else
      cat "$TEST_TMPDIR/gh.comments"
    fi
    touch "$TEST_TMPDIR/gh.listed"
    ;;
  *"--method POST "*) echo "9000000001 https://github.com/cariad/tofu/pull/7#issuecomment-9000000001" ;;
  *"--method PATCH "*)
    args=$*
    id=${args##*comments/}
    id=${id%% *}
    echo "$id https://github.com/cariad/tofu/pull/7#issuecomment-$id"
    ;;
esac
EOF
  chmod +x "$TEST_TMPDIR/bin/gh"
}
