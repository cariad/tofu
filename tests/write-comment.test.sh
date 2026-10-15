# shellcheck shell=bash
#
# Tests for scripts/write-comment.sh, with a stand-in `gh` that answers with
# responses captured from real PRs. tests/fixtures/README.md lists them.

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

# Writes DIR's comment (infra/blog's by default) for PR 18, planned at the PR's
# head unless HEAD_SHA says otherwise.
write() {
  stub_gh
  local dir=${DIR:-infra/blog}
  [[ -f $TEST_TMPDIR/body ]] || { marker "$dir" && echo 'The body.'; } >"$TEST_TMPDIR/body"
  REPO=cariad/tofu PR=18 DIR=$dir HEAD_SHA=${HEAD_SHA-$(pr_head)} BODY=$TEST_TMPDIR/body \
    PATH=$TEST_TMPDIR/bin:$PATH capture bash scripts/write-comment.sh
}

test_updates_the_existing_comment() {
  # The race left two comments for infra/new, and the older counts.
  STUB_COMMENTS=race-comments.json DIR=infra/new write
  assert_eq 0 "$status"
  assert_eq "https://github.com/cariad/tofu/pull/18#issuecomment-6186912661" "$stdout"
  assert_contains "api --method PATCH repos/cariad/tofu/issues/comments/6186912661 --input -" "$(<"$TEST_TMPDIR/gh.log")"
  [[ $(<"$TEST_TMPDIR/gh.log") != *POST* ]] || fail "it created a comment as well"
}

test_updates_the_bots_comment_not_an_older_persons() {
  # Seed 2, a person's comment with infra/blog's marker, is older than Seed 4,
  # the bot's oldest. There's no captured answer for updating Seed 4, so this
  # only checks the request.
  write
  assert_contains "api --method PATCH repos/cariad/tofu/issues/comments/6153211377 --input -" "$(<"$TEST_TMPDIR/gh.log")"
}

test_creates_a_comment_when_there_is_none() {
  DIR=infra/new write
  assert_eq 0 "$status"
  assert_eq "https://github.com/cariad/tofu/pull/18#issuecomment-6186912661" "$stdout"
  assert_contains "api --method POST repos/cariad/tofu/issues/18/comments --input -" "$(<"$TEST_TMPDIR/gh.log")"
  [[ $(<"$TEST_TMPDIR/gh.log") != *PATCH* ]] || fail "it updated a comment as well"
}

test_keeps_a_new_comment_that_won_a_race() {
  # It created the race's first comment, the older of the two.
  STUB_LATER_COMMENTS=race-comments.json DIR=infra/new write
  assert_eq 0 "$status"
  assert_eq "https://github.com/cariad/tofu/pull/18#issuecomment-6186912661" "$stdout"
  [[ $(<"$TEST_TMPDIR/gh.log") != *DELETE* ]] || fail "it deleted its comment"
}

test_gives_way_to_an_older_comment_after_losing_a_race() {
  # It created the race's second comment, the newer of the two.
  STUB_CREATED=created-2.json STUB_LATER_COMMENTS=race-comments.json DIR=infra/new write
  assert_eq 0 "$status"
  assert_contains "api --method DELETE repos/cariad/tofu/issues/comments/6186912865" "$(<"$TEST_TMPDIR/gh.log")"
  assert_contains "api --method PATCH repos/cariad/tofu/issues/comments/6186912661 --input -" "$(<"$TEST_TMPDIR/gh.log")"
  assert_eq "https://github.com/cariad/tofu/pull/18#issuecomment-6186912661" "$stdout"
}

test_lists_every_page_of_comments() {
  DIR=infra/new write
  assert_contains "api --paginate repos/cariad/tofu/issues/18/comments?per_page=100" "$(<"$TEST_TMPDIR/gh.log")"
}

test_sends_the_body_exactly() {
  {
    marker infra/new
    printf -- '-f "quoted" \\ back\\slash @file\n  é\n\n'
  } >"$TEST_TMPDIR/body"

  DIR=infra/new write
  jq -j .body "$TEST_TMPDIR/gh.stdin" | diff -u "$TEST_TMPDIR/body" -
}

test_writes_nothing_when_the_pr_has_moved_on() {
  HEAD_SHA=abc write
  assert_eq 0 "$status"
  assert_eq "" "$stdout"
  assert_eq "::notice::Not writing the plan comment, because the PR has moved on from abc to $(pr_head)." "$stderr"
  assert_eq "api repos/cariad/tofu/pulls/18 --jq .head.sha" "$(<"$TEST_TMPDIR/gh.log")"
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
  FAIL_CALL=pulls/18 write
  assert_eq 1 "$status"
  assert_eq "api repos/cariad/tofu/pulls/18 --jq .head.sha" "$(<"$TEST_TMPDIR/gh.log")"
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
