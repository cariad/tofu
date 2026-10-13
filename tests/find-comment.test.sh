# shellcheck shell=bash
#
# Tests for scripts/find-comment.sh, against comments captured from a real PR.
# tests/fixtures/README.md lists what each seed comment is.

# shellcheck source=tests/lib/assert.sh
source tests/lib/assert.sh

# Finds DIR's comment in FILE (the captured comments by default), and sets
# `seed` to the found comment's second line, or to nothing.
#
# Usage: find_comment DIR [FILE]
find_comment() {
  DIR=$1 capture bash scripts/find-comment.sh <"${2:-tests/fixtures/github/comments.json}"
  assert_eq 0 "$status"
  seed=$(jq -r '.body | split("\n")[1]' <<<"$stdout")
}

test_the_capture_has_every_seed() {
  assert_eq 9 "$(jq length tests/fixtures/github/comments.json)"
}

test_finds_the_bots_oldest_comment_for_the_directory() {
  # Seed 2, a person's copy of the marker, is older still.
  find_comment infra/blog
  assert_eq "Seed 4: the bot's first comment for infra/blog." "$seed"
}

test_reads_pages_as_separate_arrays_too() {
  # Pages of two, as `gh` prints them to a terminal.
  jq -c 'range(0; length; 2) as $i | .[$i:$i + 2]' tests/fixtures/github/comments.json >"$TEST_TMPDIR/pages"
  find_comment infra/blog "$TEST_TMPDIR/pages"
  assert_eq "Seed 4: the bot's first comment for infra/blog." "$seed"
}

test_finds_another_directorys_comment() {
  find_comment infra/other
  assert_eq "Seed 3: the bot's comment for infra/other." "$seed"
}

test_matches_the_whole_directory() {
  find_comment infra/blog-old
  assert_eq "Seed 8: the bot's comment for infra/blog-old." "$seed"
  find_comment infra
  assert_eq "" "$stdout"
}

test_ignores_a_marker_that_is_not_on_line_1() {
  find_comment infra/second-line
  assert_eq "" "$stdout"
}

test_prints_nothing_without_a_comment() {
  find_comment infra/missing
  assert_eq "" "$stdout"
}
