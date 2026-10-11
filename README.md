# tofu

GitHub Actions to plan and apply OpenTofu changes

## Development

### Required tools

- [mise](https://mise.jdx.dev/)

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

1. `mise install` will install the GitHub CLI, which you'll need to sign into for `zizmor`'s online audits of the GitHub Actions files.

   ```bash
   mise exec -- gh auth login
   ```

1. To verify the setup, run the linters and check they all pass.

   ```bash
   mise run lint
   ```
