# shellcheck shell=bash
#
# Checks that the fixtures' plan JSON has the fields the fingerprint reads,
# under the names it uses. Some fields only appear in some plans, so each of
# those is also checked in a fixture where it must appear; otherwise a wrong
# name would never be noticed. No fixture has a `deposed` object.

# shellcheck source=tests/lib/assert.sh
source tests/lib/assert.sh

# Fails unless the jq FILTER is true for the plan JSON in FILE.
#
# Usage: check FILE FILTER
check() {
  assert_eq "$1: true" "$1: $(jq "$2" "$1")"
}

test_every_plan_has_the_fields_the_fingerprint_reads() {
  local file
  for file in tests/fixtures/*/plan*.json; do
    check "$file" '.terraform_version | type == "string"'

    check "$file" '[.resource_changes[]? |
      (.address | type == "string")
      and (.change | has("actions") and has("after") and has("after_unknown") and has("after_sensitive"))
      and (.change.actions | type == "array")
      and (.previous_address | . == null or type == "string")
      and (.deposed | . == null or type == "string")
      and (.change.importing | . == null or (.id | type == "string"))
      and (.change.replace_paths | . == null or type == "array")
    ] | all'

    check "$file" '[.output_changes // {} | .[] |
      has("actions") and has("after") and has("after_unknown") and has("after_sensitive")
    ] | all'
  done
}

test_a_move_has_a_previous_address() {
  check tests/fixtures/move-only/plan.json \
    '.resource_changes[0] | .previous_address == "terraform_data.old" and .change.actions == ["no-op"]'
}

test_an_import_has_an_importing_id() {
  check tests/fixtures/import-only-a/plan.json \
    '.resource_changes[0].change | .importing.id == "example-a" and .actions == ["no-op"]'
}

test_a_replacement_has_replace_paths() {
  check tests/fixtures/replacement/plan.json \
    '.resource_changes[0].change | .replace_paths == [["triggers_replace"]] and .actions == ["delete", "create"]'
}

test_a_sensitive_value_is_marked_in_after_sensitive() {
  check tests/fixtures/sensitive-a/plan.json \
    '.resource_changes[0].change.after_sensitive.input == true'
}

test_an_unknown_value_is_marked_in_after_unknown() {
  check tests/fixtures/changes/plan.json \
    '.resource_changes[0].change.after_unknown.id == true'
}

test_an_output_change_is_in_output_changes() {
  check tests/fixtures/output-only/plan.json \
    '.output_changes.example | .actions == ["create"] and .after == "example"'
}
