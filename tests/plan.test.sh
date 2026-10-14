# shellcheck shell=bash
#
# Tests for scripts/plan.sh, with a stand-in `tofu` that prints the real plans
# of the fixture it's pointed at. The stand-in is first on the PATH, so the
# tests never reach a real `tofu`.

# shellcheck source=tests/lib/assert.sh
source tests/lib/assert.sh

# Puts a stand-in `tofu` in $TEST_TMPDIR/bin. It logs each call's arguments to
# $TEST_TMPDIR/tofu.log.
#
# - `init` exits INIT_STATUS (default 0).
# - `plan` writes a plan file to its `-out` path, notes what it sees in
#   $TEST_TMPDIR/tofu.seen, prints PLAN_SAYS if it's set, and exits PLAN_STATUS
#   (default 2). With PLAN_HANGS set, it writes its PID to $TEST_TMPDIR/tofu.pid
#   and sleeps instead.
# - `show` prints the `-chdir` directory's plan.txt, or plan.json with `-json`,
#   and exits SHOW_STATUS (default 0).
stub_tofu() {
  mkdir -p "$TEST_TMPDIR/bin"
  cat >"$TEST_TMPDIR/bin/tofu" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"$TEST_TMPDIR/tofu.log"
dir=${1#-chdir=}
case "$1 ${2:-}" in
  "version ") echo "OpenTofu v1.13.1" ;;
  *" init") exit "${INIT_STATUS:-0}" ;;
  *" plan")
    # `-out=FILE` is the last argument.
    out=${!#}
    out=${out#-out=}
    echo 'A plan file' >"$out"
    {
      echo "umask $(umask)"
      # `find -perm` prints the directory only if its mode is exactly 700.
      echo "private $(find "${out%/*}" -maxdepth 0 -perm 700)"
      echo "TF_IN_AUTOMATION=${TF_IN_AUTOMATION-unset} TF_INPUT=${TF_INPUT-unset} TF_LOG=${TF_LOG-unset}"
    } >"$TEST_TMPDIR/tofu.seen"
    [[ -z ${PLAN_SAYS:-} ]] || echo "$PLAN_SAYS"
    if [[ -n ${PLAN_HANGS:-} ]]; then
      echo $$ >"$TEST_TMPDIR/tofu.pid"
      exec sleep 60
    fi
    exit "${PLAN_STATUS:-2}"
    ;;
  *" show")
    if [[ $3 == -json ]]; then cat "$dir/plan.json"; else cat "$dir/plan.txt"; fi
    exit "${SHOW_STATUS:-0}"
    ;;
esac
EOF
  chmod +x "$TEST_TMPDIR/bin/tofu"
  mkdir -p "$TEST_TMPDIR/runner-temp"
  [[ -e $TEST_TMPDIR/event.json ]] || echo '{"pull_request": {"head": {"sha": "0123abc"}}}' >"$TEST_TMPDIR/event.json"
}

# Runs COMMAND with the environment the runner gives the plan action's step on a
# pull_request, with the stand-in `tofu` first on the PATH. Set EVENT,
# WORKING_DIRECTORY or STEP_PATH to change those.
#
# Usage: in_step COMMAND [ARG...]
in_step() {
  env GITHUB_EVENT_NAME="${EVENT-pull_request}" \
    GITHUB_EVENT_PATH="$TEST_TMPDIR/event.json" \
    GITHUB_OUTPUT="$TEST_TMPDIR/output" \
    GITHUB_STEP_SUMMARY="$TEST_TMPDIR/summary" \
    GITHUB_SERVER_URL=https://github.com \
    GITHUB_REPOSITORY=cariad/tofu \
    GITHUB_RUN_ID=1 \
    RUNNER_TEMP="$TEST_TMPDIR/runner-temp" \
    WORKING_DIRECTORY="${WORKING_DIRECTORY-tests/fixtures/changes}" \
    PATH="${STEP_PATH-$TEST_TMPDIR/bin:$PATH}" \
    "$@"
}

# Runs scripts/plan.sh as the plan action's step.
run_plan() {
  stub_tofu
  touch "$TEST_TMPDIR/output" "$TEST_TMPDIR/summary"
  capture in_step "$BASH" scripts/plan.sh
}

# Prints what render-comment.sh renders for FIXTURE with STATUS.
#
# Usage: rendered FIXTURE STATUS
rendered() {
  DIR=tests/fixtures/$1 STATUS=$2 SHA=0123abc RUN_URL=https://github.com/cariad/tofu/actions/runs/1 \
    PLAN_TEXT=tests/fixtures/$1/plan.txt PLAN_JSON=tests/fixtures/$1/plan.json \
    bash scripts/render-comment.sh
}

# Prints the stand-in's log with the private directory's path replaced by TMP.
tofu_log() {
  sed -E "s|$TEST_TMPDIR/runner-temp/cariad-tofu\.[A-Za-z0-9]+|TMP|g" "$TEST_TMPDIR/tofu.log"
}

test_plans_a_root_module_with_changes() {
  run_plan
  assert_eq 0 "$status"
  assert_eq "changes=true" "$(<"$TEST_TMPDIR/output")"
  rendered changes planned | diff -u - "$TEST_TMPDIR/summary"
  assert_eq "version
-chdir=tests/fixtures/changes init -input=false -lockfile=readonly
-chdir=tests/fixtures/changes plan -input=false -lock=false -no-color -detailed-exitcode -out=TMP/plan
-chdir=tests/fixtures/changes show -no-color TMP/plan
-chdir=tests/fixtures/changes show -json TMP/plan" "$(tofu_log)"
}

test_plans_a_root_module_without_changes() {
  WORKING_DIRECTORY=tests/fixtures/empty PLAN_STATUS=0 run_plan
  assert_eq 0 "$status"
  assert_eq "changes=false" "$(<"$TEST_TMPDIR/output")"
  rendered empty planned | diff -u - "$TEST_TMPDIR/summary"
}

test_reports_a_failed_plan() {
  WORKING_DIRECTORY=tests/fixtures/failing-precondition PLAN_STATUS=1 run_plan
  assert_eq 1 "$status"
  assert_contains "::error::The plan for tests/fixtures/failing-precondition failed." "$stderr"
  assert_eq "" "$(<"$TEST_TMPDIR/output")"
  rendered failing-precondition plan-failed | diff -u - "$TEST_TMPDIR/summary"
  [[ $(<"$TEST_TMPDIR/tofu.log") != *show* ]] || fail "it showed a failed plan"
}

test_reports_a_failed_init_as_a_failed_plan() {
  INIT_STATUS=1 run_plan
  assert_eq 1 "$status"
  rendered changes plan-failed | diff -u - "$TEST_TMPDIR/summary"
  [[ $(<"$TEST_TMPDIR/tofu.log") != *plan* ]] || fail "it planned after init failed"
}

test_reports_a_failed_show_as_a_failed_plan() {
  SHOW_STATUS=1 run_plan
  assert_eq 1 "$status"
  rendered changes plan-failed | diff -u - "$TEST_TMPDIR/summary"
}

test_deletes_the_plan_when_it_finishes() {
  run_plan
  assert_eq "" "$(ls -A "$TEST_TMPDIR/runner-temp")"
  PLAN_STATUS=1 run_plan
  assert_eq "" "$(ls -A "$TEST_TMPDIR/runner-temp")"
}

test_keeps_the_plan_private() {
  run_plan
  assert_contains "umask 0077" "$(<"$TEST_TMPDIR/tofu.seen")"
  assert_contains "private $TEST_TMPDIR/runner-temp/cariad-tofu." "$(<"$TEST_TMPDIR/tofu.seen")"
}

test_stops_workflow_commands_while_tofu_runs() {
  PLAN_SAYS='  ::set-output name=changes::false' run_plan
  local token
  token=$(sed -n 's/^::stop-commands::\([0-9a-f]\{32\}\)$/\1/p' <<<"$stdout")
  [[ -n $token ]] || fail "it didn't stop workflow commands with a random token"
  assert_eq "::stop-commands::$token
  ::set-output name=changes::false
::$token::" "$(grep -e '::' <<<"$stdout")"
}

test_runs_tofu_for_automation_without_logs() {
  TF_LOG=trace run_plan
  assert_contains "TF_IN_AUTOMATION=1 TF_INPUT=0 TF_LOG=unset" "$(<"$TEST_TMPDIR/tofu.seen")"
}

test_refuses_other_events() {
  EVENT=pull_request_target run_plan
  assert_eq 1 "$status"
  assert_eq "::error::The plan action only runs on pull_request, not pull_request_target." "$stderr"
  [[ ! -e $TEST_TMPDIR/tofu.log ]] || fail "it ran tofu anyway"
}

test_refuses_an_event_without_a_head_commit() {
  echo '{"pull_request": {}}' >"$TEST_TMPDIR/event.json"
  run_plan
  assert_eq 1 "$status"
  assert_eq "::error::The pull_request event has no head commit." "$stderr"
  [[ ! -e $TEST_TMPDIR/tofu.log ]] || fail "it ran tofu anyway"
}

test_plans_the_workspace_root_by_default() {
  stub_tofu
  touch "$TEST_TMPDIR/output" "$TEST_TMPDIR/summary"
  # The action's default, `.`, run from inside a fixture.
  # shellcheck disable=SC2016 # $0 is for the inner bash.
  WORKING_DIRECTORY=. capture in_step bash -c 'cd tests/fixtures/changes && exec "$0" ../../../scripts/plan.sh' "$BASH"
  assert_eq 0 "$status"
  assert_contains "-chdir=. init" "$(<"$TEST_TMPDIR/tofu.log")"
  assert_contains "### OpenTofu plan for \`.\`" "$(<"$TEST_TMPDIR/summary")"
}

test_tidies_the_working_directory() {
  WORKING_DIRECTORY=./tests/fixtures/changes// run_plan
  assert_eq 0 "$status"
  assert_contains "-chdir=tests/fixtures/changes init" "$(<"$TEST_TMPDIR/tofu.log")"
  rendered changes planned | diff -u - "$TEST_TMPDIR/summary"
}

test_refuses_a_working_directory_with_other_characters() {
  local dir
  for dir in '' ./ / 'tests/fixtures/chan ges' $'tests/fixtures\n::warning::x' 'tests/fixtures/changes;x' 'tésts' 'tests\fixtures'; do
    WORKING_DIRECTORY=$dir run_plan
    assert_eq "$dir: 1" "$dir: $status"
    assert_eq "::error::working-directory must be a directory whose name has only A-Z, a-z, 0-9, ., _, / and -." "$stderr"
  done
  [[ ! -e $TEST_TMPDIR/tofu.log ]] || fail "it ran tofu anyway"
}

test_refuses_a_working_directory_outside_the_workspace_or_spelt_oddly() {
  local dir

  for dir in /tmp .. ../tests tests//fixtures/changes tests/./fixtures/changes ././tests/fixtures/changes tests/fixtures/changes/..; do
    WORKING_DIRECTORY=$dir run_plan
    assert_eq "$dir: 1" "$dir: $status"
    assert_eq "::error::working-directory must be a path inside the workspace, such as infra/blog, without empty, . or .. parts." "$stderr"
  done

  [[ ! -e $TEST_TMPDIR/tofu.log ]] || fail "it ran tofu anyway"
}

test_refuses_a_working_directory_that_does_not_exist() {
  WORKING_DIRECTORY=tests/fixtures/missing run_plan
  assert_eq 1 "$status"
  assert_eq "::error::working-directory tests/fixtures/missing isn't a directory." "$stderr"
}

test_needs_tofu() {
  STEP_PATH=$TEST_TMPDIR/nothing run_plan
  assert_eq 1 "$status"
  assert_eq "::error::tofu isn't on the PATH. Install OpenTofu before the plan action." "$stderr"
}

test_needs_jq() {
  STEP_PATH=$TEST_TMPDIR/bin run_plan
  assert_eq 1 "$status"
  assert_eq "::error::jq isn't on the PATH. The plan action needs a GitHub-hosted Ubuntu runner." "$stderr"
}

# Puts a stand-in `jq` in $TEST_TMPDIR/bin that fails any program containing
# PATTERN, as an older or newer jq would, and runs the real jq otherwise.
#
# Usage: stub_jq PATTERN
stub_jq() {
  mkdir -p "$TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\n[[ $* == *%q* ]] && exit 3\nexec %q "$@"\n' "$1" "$(command -v jq)" >"$TEST_TMPDIR/bin/jq"
  chmod +x "$TEST_TMPDIR/bin/jq"
}

test_refuses_jq_1_6() {
  # shellcheck disable=SC2016 # A jq variable, not a bash one.
  stub_jq '$import'
  run_plan
  assert_eq 1 "$status"
  assert_eq "::error::The runner's jq is too old. The plan action needs jq 1.7 or later." "$stderr"
}

# Runs the action's `run:` line as the runner does, stops it as the runner does
# when the job is cancelled or times out, and checks that tofu stops and the
# plan is deleted.
#
# A bash started in the background ignores SIGINT, so only the runner's SIGTERM
# is sent here.
test_deletes_the_plan_when_the_runner_stops_the_step() {
  stub_tofu
  sed -n 's/^ *run: //p' plan/action.yml >"$TEST_TMPDIR/step.sh"
  PLAN_HANGS=1 GITHUB_ACTION_PATH=$PWD/plan in_step \
    bash --noprofile --norc -e -o pipefail "$TEST_TMPDIR/step.sh" >/dev/null 2>&1 &
  local pid=$! i
  for ((i = 0; i < 100; i++)); do
    [[ -s $TEST_TMPDIR/tofu.pid ]] && break
    sleep 0.1
  done

  [[ -s $TEST_TMPDIR/tofu.pid ]] || fail "tofu plan never started"

  # $pid is the subshell running in_step. The runner signals the step's own
  # process, plan.sh after its `exec`, which started tofu.
  kill -TERM $(($(ps -o ppid= -p "$(<"$TEST_TMPDIR/tofu.pid")")))

  status=0
  wait "$pid" || status=$?
  assert_eq 143 "$status"
  assert_eq "" "$(ls -A "$TEST_TMPDIR/runner-temp")"

  for ((i = 0; i < 10; i++)); do
    kill -0 "$(<"$TEST_TMPDIR/tofu.pid")" 2>/dev/null || return 0
    sleep 0.1
  done

  kill "$(<"$TEST_TMPDIR/tofu.pid")"
  fail "tofu kept running"
}
