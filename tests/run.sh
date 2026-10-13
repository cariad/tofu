#!/usr/bin/env bash
#
# Runs every `test_*` function in tests/**/*.test.sh, each in a new bash
# process with `set -euo pipefail`, no stdin and an empty directory in
# TEST_TMPDIR.
#
# A test file is loaded once to list its tests, then again for each test, so
# its top level should only source helpers and define functions.

if ((BASH_VERSINFO[0] < 5)); then
  echo "The tests need bash 5 or later, but this is bash $BASH_VERSION." >&2
  exit 1
fi

cd "$(dirname "$0")/.." || exit 1
shopt -s globstar
failed=0

for file in tests/**/*.test.sh; do
  # `set -e` stops a file that doesn't load before `compgen` lists its tests.
  # (`_` fills `$0`, so the file is `$1`.)
  names=$(bash -c 'set -euo pipefail; source "$1"; compgen -A function test_' _ "$file")

  if [[ -z $names ]]; then
    echo "FAIL $file (doesn't load or has no tests)"
    failed=1
    continue
  fi

  for name in $names; do
    tmp=$(mktemp -d)

    # A new bash process, unlike a subshell, keeps `set -e` on inside this `if`,
    # and can't see the runner's variables.
    if TEST_TMPDIR=$tmp bash -c 'set -euo pipefail; source "$1"; "$2"' _ "$file" "$name" </dev/null; then
      echo "ok   $file $name"
    else
      echo "FAIL $file $name"
      failed=1
    fi

    rm -rf "$tmp"
  done
done

exit "$failed"
