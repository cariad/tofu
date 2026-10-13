# tofu

GitHub Actions to plan and apply OpenTofu changes

## Development

### Required tools

- [mise](https://mise.jdx.dev/)
- Bash 5 or later.

### Initial setup

1. Clone this repository.

   ```bash
   git clone git@github.com:cariad/tofu.git
   ```

1. Change into the repository's directory.

   ```bash
   cd tofu
   ```

1. Install the project's tools.

   ```bash
   mise install
   ```

1. Log into the GitHub CLI to enable `zizmor`'s online audits of the GitHub Actions files.

   ```bash
   mise run gh:login
   ```

1. To verify the setup, run the linters and check they all pass.

   ```bash
   mise run lint
   ```

1. Check the OpenTofu fixtures are formatted. `mise run lint` doesn't include this check.

   ```bash
   mise run lint-fixtures
   ```

### Running the tests

```bash
mise run test
```
