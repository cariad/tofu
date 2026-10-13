# shellcheck shell=bash
#
# Tests for scripts/render-comment.sh, against the real fixture plans. Edge
# cases change a copy of a real plan inside the test.
#
# shellcheck disable=SC2016 # Backticks in these strings are Markdown.
# shellcheck source=tests/lib/assert.sh
source tests/lib/assert.sh

# Renders FIXTURE's plan as a planned comment. Set PLAN_TEXT or PLAN_JSON to use
# a changed copy of its plan instead.
#
# Usage: render FIXTURE
render() {
  DIR=infra/blog STATUS=planned SHA=0123abc RUN_URL=https://example.com/run FP=${FP:-} \
    PLAN_TEXT=${PLAN_TEXT:-tests/fixtures/$1/plan.txt} \
    PLAN_JSON=${PLAN_JSON:-tests/fixtures/$1/plan.json} \
    capture bash scripts/render-comment.sh
}

# Prints the bold part of the last render's summary line.
summary() {
  sed -n 's/^\*\*\(.*\)\*\* Planned at .*/\1/p' <<<"$stdout"
}

# Prints the plan lines inside the last render's code block.
plan_in_block() {
  sed -n '/^```text$/,/^```$/{/^```/d;p;}' "$TEST_TMPDIR/stdout"
}

# Prints the size of the last render in bytes.
size() {
  echo $(($(wc -c <"$TEST_TMPDIR/stdout")))
}

# Writes a copy of FILE to $TEST_TMPDIR/plan.txt with BYTES spaces added to
# line LINE.
#
# Usage: lengthen FILE LINE BYTES
lengthen() {
  local pad
  printf -v pad '%*s' "$3" ''
  awk -v line="$2" -v pad="$pad" 'NR == line { $0 = $0 pad } { print }' "$1" >"$TEST_TMPDIR/plan.txt"
}

test_planned_body() {
  FP=abc123 render changes
  assert_eq 0 "$status"
  {
    cat <<'EOF'
<!-- cariad/tofu {"v":1,"dir":"infra/blog","status":"planned","sha":"0123abc","fp":"abc123"} -->
### OpenTofu plan for `infra/blog`

**1 to add, 0 to change, 0 to destroy.** Planned at 0123abc by OpenTofu 1.13.1 in [this run](https://example.com/run).

<details><summary>Plan</summary>

```text
EOF
    cat tests/fixtures/changes/plan.txt
    printf '```\n\n</details>\n'
  } | diff -u - "$TEST_TMPDIR/stdout"
}

test_marker_has_no_fp_without_one() {
  render changes
  assert_eq '<!-- cariad/tofu {"v":1,"dir":"infra/blog","status":"planned","sha":"0123abc"} -->' "$(head -n 1 <<<"$stdout")"
}

test_marker_escapes_angle_brackets() {
  FP='a-->b<c' render changes
  assert_eq '<!-- cariad/tofu {"v":1,"dir":"infra/blog","status":"planned","sha":"0123abc","fp":"a--\u003eb\u003cc"} -->' "$(head -n 1 <<<"$stdout")"
}

test_summary_agrees_with_opentofu() {
  local plan fixture want
  for plan in tests/fixtures/*/plan.txt; do
    fixture=$(basename "$(dirname "$plan")")
    if grep -q '^No changes\.' "$plan"; then
      want="No changes."
    else
      want=$(sed -n 's/^Plan: //p' "$plan")
      [[ -n $want ]] || continue
    fi
    render "$fixture"
    # Leave out the moves and outputs that ours adds to OpenTofu's counts.
    assert_eq "$fixture: $want" "$fixture: $(summary | sed -E 's/(, [0-9]+ (to move|outputs? to change))+\.$/./')"
  done
}

test_summary_adds_moves_and_outputs() {
  render move-only
  assert_eq "0 to add, 0 to change, 0 to destroy, 1 to move." "$(summary)"
  render output-only
  assert_eq "0 to add, 0 to change, 0 to destroy, 1 output to change." "$(summary)"
  render mixed-changes
  assert_eq "1 to add, 1 to change, 1 to destroy, 1 output to change." "$(summary)"

  jq '.output_changes.other = .output_changes.example' tests/fixtures/output-only/plan.json >"$TEST_TMPDIR/plan.json"
  PLAN_JSON=$TEST_TMPDIR/plan.json render output-only
  assert_eq "0 to add, 0 to change, 0 to destroy, 2 outputs to change." "$(summary)"
}

test_summary_counts_forgets() {
  jq '.resource_changes[0].change.actions = ["forget"]' tests/fixtures/changes/plan.json >"$TEST_TMPDIR/plan.json"
  PLAN_JSON=$TEST_TMPDIR/plan.json render changes
  assert_eq "0 to add, 0 to change, 0 to destroy, 1 to forget." "$(summary)"
}

test_summary_counts_a_data_source_read_as_a_change() {
  jq '.resource_changes[0] |= (.mode = "data" | .change.actions = ["read"])' tests/fixtures/unchanged/plan.json >"$TEST_TMPDIR/plan.json"
  PLAN_JSON=$TEST_TMPDIR/plan.json render unchanged
  assert_eq "0 to add, 0 to change, 0 to destroy." "$(summary)"
}

test_summary_ignores_an_output_whose_value_is_unchanged() {
  # As when only its sensitivity changes.
  jq '.output_changes.example |= (.before = .after | .actions = ["update"])' tests/fixtures/output-only/plan.json >"$TEST_TMPDIR/plan.json"
  PLAN_JSON=$TEST_TMPDIR/plan.json render output-only
  assert_eq "No changes." "$(summary)"
}

test_fence_is_longer_than_any_backticks_in_the_plan() {
  cp tests/fixtures/changes/plan.txt "$TEST_TMPDIR/plan.txt"
  printf 'a ` ````\n' >>"$TEST_TMPDIR/plan.txt"
  PLAN_TEXT=$TEST_TMPDIR/plan.txt render changes
  assert_contains $'\n`````text\n' "$stdout"
  assert_contains $'\na ` ````\n`````\n' "$stdout"
}

test_large_plan_is_cut_at_a_line_to_fit() {
  render large
  assert_eq 0 "$status"
  (($(size) <= 65536)) || fail "the body is $(size) bytes"
  (($(size) > 65000)) || fail "the body is only $(size) bytes, so it wastes space"
  assert_contains $'\n</details>\n\nThe plan is too long for a comment, so it\'s cut short. See all of it in [this run](https://example.com/run).' "$stdout"

  # What's kept is the plan's first lines, whole.
  plan_in_block >"$TEST_TMPDIR/kept"
  head -n "$(wc -l <"$TEST_TMPDIR/kept")" tests/fixtures/large/plan.txt | diff -u - "$TEST_TMPDIR/kept"
}

test_body_can_fill_the_limit_without_a_cut() {
  render changes
  local spare=$((65536 - $(size)))
  lengthen tests/fixtures/changes/plan.txt 1 "$spare"
  PLAN_TEXT=$TEST_TMPDIR/plan.txt render changes
  assert_eq 65536 "$(size)"
  [[ $stdout != *"cut short"* ]] || fail "a plan that fits was cut short"

  lengthen tests/fixtures/changes/plan.txt 1 $((spare + 1))
  PLAN_TEXT=$TEST_TMPDIR/plan.txt render changes
  assert_contains "cut short" "$stdout"
}

test_cut_can_fill_the_limit() {
  render large
  local kept pad
  kept=$(($(plan_in_block | wc -l)))
  printf -v pad '%*s' $((65536 - $(size))) ''
  # Fill the last kept line to the limit, then add a blank line, which mustn't
  # squeeze in after it.
  awk -v line="$kept" -v pad="$pad" 'NR == line { print $0 pad; print ""; next } { print }' \
    tests/fixtures/large/plan.txt >"$TEST_TMPDIR/plan.txt"
  PLAN_TEXT=$TEST_TMPDIR/plan.txt render large
  assert_eq 65536 "$(size)"
  assert_eq "$kept" $(($(plan_in_block | wc -l)))
}

test_cut_counts_bytes_not_characters() {
  # Each "é" is two bytes, so counting characters would cut far more of the
  # plan than it needs to.
  sed 's/example/éééééééééé/g' tests/fixtures/large/plan.txt >"$TEST_TMPDIR/plan.txt"
  PLAN_TEXT=$TEST_TMPDIR/plan.txt render large
  (($(size) <= 65536)) || fail "the body is $(size) bytes"
  (($(size) > 65000)) || fail "the body is only $(size) bytes, so it wastes space"
}

test_plan_failed_body() {
  DIR=infra/blog STATUS=plan-failed SHA=0123abc RUN_URL=https://example.com/run FP=abc123 \
    PLAN_TEXT=tests/fixtures/failing-precondition/plan.txt \
    PLAN_JSON=tests/fixtures/failing-precondition/plan.json \
    capture bash scripts/render-comment.sh
  assert_eq 0 "$status"
  assert_eq '<!-- cariad/tofu {"v":1,"dir":"infra/blog","status":"plan-failed","sha":"0123abc"} -->
### OpenTofu plan for `infra/blog`

**The plan failed** at 0123abc in [this run](https://example.com/run).' "$stdout"
}

test_unknown_status_fails() {
  DIR=infra/blog STATUS=applied SHA=0123abc RUN_URL=https://example.com/run \
    capture bash scripts/render-comment.sh
  assert_eq 1 "$status"
  assert_contains 'STATUS must be planned or plan-failed' "$stderr"
}
