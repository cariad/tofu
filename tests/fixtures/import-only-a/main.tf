# `terraform_data` accepts any import ID. The resource sets no arguments, so
# the plan only imports it. `import-only-a/` and `import-only-b/` differ only
# in the ID.

terraform {
  # Keep in sync with `.config/mise.toml`•`lint-fixtures`•`tools`•`opentofu`:
  required_version = "~> 1.13.1"
}

import {
  to = terraform_data.example
  id = "example-a"
}

resource "terraform_data" "example" {}
