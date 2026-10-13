# shellcheck shell=bash
#
# Helpers for the tests. Each test file sources this.
#
# Runs a command, such as `bash scripts/x.sh`, without stopping the test if it
# fails, and sets `status`, `stdout` and `stderr`.
#
# `$stdout` and `$stderr` lose trailing newlines. When those matter, compare
# the files instead, such as with `diff -u FIXTURE "$TEST_TMPDIR/stdout"`.
#
# Run scripts, not shell functions: bash ignores `set -e` inside a function
# run here, so it wouldn't stop at a failure.
#
# Usage: [NAME=VALUE...] capture COMMAND [ARG...] [<FILE]
#
# shellcheck disable=SC2034 # The tests read the variables.
capture() {
  status=0
  "$@" >"$TEST_TMPDIR/stdout" 2>"$TEST_TMPDIR/stderr" || status=$?
  stdout=$(cat "$TEST_TMPDIR/stdout")
  stderr=$(cat "$TEST_TMPDIR/stderr")
}

# Usage: assert_eq WANT GOT
assert_eq() {
  if [[ $1 != "$2" ]]; then
    echo "want: $1" >&2
    echo "got:  $2" >&2
    return 1
  fi
}
