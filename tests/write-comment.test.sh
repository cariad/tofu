# shellcheck shell=bash
#
# Tests for scripts/write-comment.sh, with a stand-in `gh` that lists the
# comments captured from a real PR.

# shellcheck source=tests/lib/assert.sh
source tests/lib/assert.sh

# Puts a stand-in `gh` in $TEST_TMPDIR/bin. It logs each call's arguments to
# $TEST_TMPDIR/gh.log and any request body to $TEST_TMPDIR/gh.stdin. It prints
# GH_HEAD (or `abc`) as the PR's head, the captured comments as the listing, and
# a URL for a write. A call whose arguments contain GH_FAIL fails instead.
stub_gh() {
  mkdir -p "$TEST_TMPDIR/bin"
  cat >"$TEST_TMPDIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$TEST_TMPDIR/gh.log"
if [[ $* == *--input* ]]; then
  cat >"$TEST_TMPDIR/gh.stdin"
fi
if [[ -n ${GH_FAIL:-} && $* == *"$GH_FAIL"* ]]; then
  echo "gh: the call failed" >&2
  exit 1
fi
case $* in
  *" repos/cariad/tofu/pulls/7 "*) echo "${GH_HEAD:-abc}" ;;
  *--paginate*) cat tests/fixtures/github/comments.json ;;
  *) echo "https://github.com/cariad/tofu/pull/7#issuecomment-1" ;;
esac
EOF
  chmod +x "$TEST_TMPDIR/bin/gh"
}

# Prints a marker line for DIR.
#
# Usage: marker DIR
marker() {
  printf '<!-- cariad/tofu {"v":1,"dir":"%s"} -->\n' "$1"
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
  assert_eq "https://github.com/cariad/tofu/pull/7#issuecomment-1" "$stdout"
  # Seed 4 is the bot's oldest comment for infra/blog.
  assert_contains "api --method PATCH repos/cariad/tofu/issues/comments/6153211377 --input - --jq .html_url" "$(<"$TEST_TMPDIR/gh.log")"
  [[ $(<"$TEST_TMPDIR/gh.log") != *POST* ]] || fail "it created a comment as well"
}

test_creates_a_comment_when_there_is_none() {
  DIR=infra/new write
  assert_eq 0 "$status"
  assert_contains "api --method POST repos/cariad/tofu/issues/7/comments --input - --jq .html_url" "$(<"$TEST_TMPDIR/gh.log")"
  [[ $(<"$TEST_TMPDIR/gh.log") != *PATCH* ]] || fail "it updated a comment as well"
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
  GH_HEAD=def write
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
  GH_FAIL=pulls/7 write
  assert_eq 1 "$status"
  assert_eq "api repos/cariad/tofu/pulls/7 --jq .head.sha" "$(<"$TEST_TMPDIR/gh.log")"
}

test_fails_when_listing_the_comments_fails() {
  GH_FAIL=--paginate write
  assert_eq 1 "$status"
  [[ $(<"$TEST_TMPDIR/gh.log") != *--method* ]] || fail "it wrote a comment anyway"
}

test_fails_when_writing_the_comment_fails() {
  GH_FAIL=PATCH write
  assert_eq 1 "$status"
  assert_contains "gh: the call failed" "$stderr"
}
