# shellcheck shell=bash
#
# Tests for the test harness: tests/run.sh and tests/lib/assert.sh.

# shellcheck source=tests/lib/assert.sh
source tests/lib/assert.sh

test_capture() {
  capture bash -c 'echo out; echo err >&2; exit 3'
  assert_eq 3 "$status"
  assert_eq out "$stdout"
  assert_eq err "$stderr"
}

test_assert_eq_fails_when_the_values_differ() {
  capture bash -c 'source tests/lib/assert.sh; assert_eq want got'
  # Plain checks, because a broken assert_eq can't be trusted to check itself.
  [[ $status == 1 ]]
  [[ $stderr == $'want: want\ngot:  got' ]]
}

test_assert_contains_fails_when_the_text_is_missing() {
  capture bash -c 'source tests/lib/assert.sh; assert_contains want got'
  [[ $status == 1 ]]
  [[ $stderr == $'want to contain: want\ngot:             got' ]]
}

# Runs a copy of tests/run.sh in an empty directory, with one test file that
# holds CONTENT.
#
# Usage: run_sample CONTENT
run_sample() {
  mkdir "$TEST_TMPDIR/tests"
  cp tests/run.sh "$TEST_TMPDIR/tests/"
  printf '%s\n' "$1" >"$TEST_TMPDIR/tests/x.test.sh"
  capture bash "$TEST_TMPDIR/tests/run.sh"
}

test_runner_stops_a_test_at_its_first_failure() {
  run_sample 'test_x() { false; echo reached; }'
  assert_eq 1 "$status"
  assert_eq "FAIL tests/x.test.sh test_x" "$stdout"
}

test_runner_fails_a_file_with_no_tests() {
  run_sample 'true'
  assert_eq 1 "$status"
  assert_eq "FAIL tests/x.test.sh (doesn't load or has no tests)" "$stdout"
}
