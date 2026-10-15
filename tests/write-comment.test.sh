# shellcheck shell=bash
#
# Tests for scripts/write-comment.sh, with a stand-in `gh` that lists the
# comments captured from a real PR.

# shellcheck source=tests/lib/assert.sh
source tests/lib/assert.sh

# shellcheck source=tests/lib/gh.sh
source tests/lib/gh.sh

# Prints a marker line for DIR.
#
# Usage: marker DIR
marker() {
  printf '<!-- cariad/tofu {"v":1,"dir":"%s"} -->\n' "$1"
}

# Makes every listing after the first include copies of Seed 4, moved to
# infra/new, with the given IDs, as if other runs had just created them.
#
# Usage: also_created ID...
also_created() {
  local ids
  ids=$(printf '%s,' "$@")
  jq --argjson ids "[${ids%,}]" --arg marker "$(marker infra/new)" '
    [.[] | select(.id == 6153211377)][0] as $seed
    | [$ids[] | $seed + {id: ., body: $marker}]' \
    tests/fixtures/github/comments.json >"$TEST_TMPDIR/gh.extra"
}

# Writes DIR's comment (infra/blog's by default) for PR 7, planned at `abc`.
write() {
  stub_gh
  local dir=${DIR:-infra/blog}
  [[ -f $TEST_TMPDIR/body ]] || { marker "$dir" && echo 'The body.'; } >"$TEST_TMPDIR/body"
  REPO=cariad/tofu PR=7 DIR=$dir HEAD_SHA=${HEAD_SHA-abc} BODY=$TEST_TMPDIR/body \
    PATH=$TEST_TMPDIR/bin:$PATH capture bash scripts/write-comment.sh
}

test_updates_the_existing_comment() {
  write
  assert_eq 0 "$status"
  # Seed 4 is the bot's oldest comment for infra/blog.
  assert_eq "https://github.com/cariad/tofu/pull/7#issuecomment-6153211377" "$stdout"
  assert_contains "api --method PATCH repos/cariad/tofu/issues/comments/6153211377 --input -" "$(<"$TEST_TMPDIR/gh.log")"
  [[ $(<"$TEST_TMPDIR/gh.log") != *POST* ]] || fail "it created a comment as well"
}

test_creates_a_comment_when_there_is_none() {
  DIR=infra/new write
  assert_eq 0 "$status"
  assert_eq "https://github.com/cariad/tofu/pull/7#issuecomment-9000000001" "$stdout"
  assert_contains "api --method POST repos/cariad/tofu/issues/7/comments --input -" "$(<"$TEST_TMPDIR/gh.log")"
  [[ $(<"$TEST_TMPDIR/gh.log") != *PATCH* ]] || fail "it updated a comment as well"
}

test_keeps_a_new_comment_that_won_a_race() {
  also_created 9000000001
  DIR=infra/new write
  assert_eq 0 "$status"
  assert_eq "https://github.com/cariad/tofu/pull/7#issuecomment-9000000001" "$stdout"
  [[ $(<"$TEST_TMPDIR/gh.log") != *DELETE* ]] || fail "it deleted its comment"
}

test_gives_way_to_an_older_comment_after_losing_a_race() {
  also_created 9000000000 9000000001
  DIR=infra/new write
  assert_eq 0 "$status"
  assert_contains "api --method DELETE repos/cariad/tofu/issues/comments/9000000001" "$(<"$TEST_TMPDIR/gh.log")"
  assert_contains "api --method PATCH repos/cariad/tofu/issues/comments/9000000000 --input -" "$(<"$TEST_TMPDIR/gh.log")"
  assert_eq "https://github.com/cariad/tofu/pull/7#issuecomment-9000000000" "$stdout"
}

test_lists_every_page_of_comments() {
  write
  assert_contains "api --paginate repos/cariad/tofu/issues/7/comments?per_page=100" "$(<"$TEST_TMPDIR/gh.log")"
}

test_sends_the_body_exactly() {
  {
    marker infra/blog
    printf -- '-f "quoted" \\ back\\slash @file\n  é\n\n'
  } >"$TEST_TMPDIR/body"
  write
  jq -j .body "$TEST_TMPDIR/gh.stdin" | diff -u "$TEST_TMPDIR/body" -
}

test_writes_nothing_when_the_pr_has_moved_on() {
  PR_HEAD=def write
  assert_eq 0 "$status"
  assert_eq "" "$stdout"
  assert_eq "::notice::Not writing the plan comment, because the PR has moved on from abc to def." "$stderr"
  assert_eq "api repos/cariad/tofu/pulls/7 --jq .head.sha" "$(<"$TEST_TMPDIR/gh.log")"
}

test_fails_when_an_input_is_empty() {
  HEAD_SHA='' write
  assert_eq 1 "$status"
  assert_contains "HEAD_SHA" "$stderr"
  [[ ! -e $TEST_TMPDIR/gh.log ]] || fail "it called gh anyway"
}

test_fails_when_the_body_is_for_another_directory() {
  marker infra/other >"$TEST_TMPDIR/body"
  write
  assert_eq 1 "$status"
  assert_eq "BODY's marker isn't for infra/blog." "$stderr"
  [[ ! -e $TEST_TMPDIR/gh.log ]] || fail "it called gh anyway"
}

test_fails_when_the_head_check_fails() {
  FAIL_CALL=pulls/7 write
  assert_eq 1 "$status"
  assert_eq "api repos/cariad/tofu/pulls/7 --jq .head.sha" "$(<"$TEST_TMPDIR/gh.log")"
}

test_fails_when_listing_the_comments_fails() {
  FAIL_CALL=--paginate write
  assert_eq 1 "$status"
  [[ $(<"$TEST_TMPDIR/gh.log") != *--method* ]] || fail "it wrote a comment anyway"
}

test_fails_when_writing_the_comment_fails() {
  FAIL_CALL=PATCH write
  assert_eq 1 "$status"
  assert_contains "gh: the call failed" "$stderr"
}
