# OpenTofu fixtures

Each directory here is a small OpenTofu root module that uses only the built-in `terraform_data` resource and the local backend.

Its `plan.txt` and `plan.json` are the real output of `tofu show -no-color` and `tofu show -json` for its plan, and the script tests read them.

## Regenerating the plans

This runs OpenTofu:

```bash
mise run generate-fixtures
```

It plans every fixture in a temporary copy, so it never writes state, `.terraform/` or plan files here. It clears your `TF_*` and `TOFU_*` environment variables, then sets `TF_IN_AUTOMATION=1` and `TF_INPUT=0`, as the plan action will. It stops if a fixture's plan doesn't exit as the table below says, or if `large`'s text isn't over 65,536 bytes. `failing-precondition` prints its precondition error on every run; that's expected.

Never edit `plan.txt` or `plan.json` by hand; regenerate them. Every `plan.json` changes when you regenerate, because it records when it was planned. A fixture with a `before/` also gets new random IDs, which show in its `plan.txt` too.

## Prior state

A fixture with a `before/` directory is planned against the state from applying `before/` first. Planned on its own, without that state, it would only create resources.

## Adding a fixture

1. Add a directory here with a `main.tf`, and a `before/main.tf` if it needs prior state. The generator plans every directory here that has a `main.tf`, and copies only the `*.tf` files in it and its `before/`.
1. If its plan shouldn't exit 2, add it to `expected_status` in `generate.sh`.
1. Add it to the table below.
1. Run `mise run lint-fixtures`, then `mise run generate-fixtures`.

## The fixtures

The exit code is the status of `tofu plan -detailed-exitcode`: 0 for no changes, 1 for an error and 2 for changes.

| Fixture                          | Plan                                                                                                                                         | Exit code |
| -                                | -                                                                                                                                            | -         |
| `changes`                        | Creates one resource.                                                                                                                        | 2         |
| `empty`                          | Has no resources, so nothing changes.                                                                                                        | 0         |
| `failing-precondition`           | Fails on a resource's precondition.                                                                                                          | 1         |
| `import-only-a`, `import-only-b` | Only imports one resource. The two differ only in the import ID.                                                                             | 2         |
| `large`                          | Creates enough resources that its text is over 65,536 bytes.                                                                                 | 2         |
| `mixed-changes`                  | Creates, updates and deletes one resource each, and adds an output. It's planned twice against the same state, into `plan.*` and `plan-2.*`. | 2         |
| `move-only`                      | Only moves one resource.                                                                                                                     | 2         |
| `output-only`                    | Only adds an output.                                                                                                                         | 2         |
| `replacement`                    | Replaces one resource, because its `triggers_replace` changed.                                                                               | 2         |
| `sensitive-a`, `sensitive-b`     | Creates one resource. The two differ only in a sensitive value.                                                                              | 2         |
| `unchanged`                      | Has one existing resource that doesn't change.                                                                                               | 0         |

## GitHub API responses

`github/` holds real GitHub API responses, exactly as `gh` printed them. Never edit them; capture them again instead.

`github/comments.json` is a test PR's comments, captured with:

```bash
mise exec gh@2.102.0 -- gh api --paginate 'repos/cariad/tofu/issues/<PR>/comments?per_page=2' > tests/fixtures/github/comments.json
```

`per_page=2` makes `gh` fetch several pages, which it joins into one array. The seed comments, oldest first:

| Seed | Author | First line |
| --- | --- | --- |
| 1 | A person | No marker. |
| 2 | A person | A marker for `infra/blog`. |
| 3 | The bot | A marker for `infra/other`. |
| 4 | The bot | A marker for `infra/blog`. |
| 5 | The bot | No marker. |
| 6 | The bot | No marker; its marker for `infra/second-line` is on line 2. |
| 7 | The bot | A marker for `infra/blog`. |
| 8 | The bot | A marker for `infra/blog-old`. |
| 9 | The bot | A marker that isn't JSON. |
