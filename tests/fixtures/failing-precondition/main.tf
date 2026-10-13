# The condition reads a local because OpenTofu rejects a literal
# `condition = false` as invalid configuration.

terraform {
  # Keep in sync with `.config/mise.toml`•`lint-fixtures`•`tools`•`opentofu`:
  required_version = "~> 1.13.1"
}

locals {
  ready = false
}

resource "terraform_data" "example" {
  lifecycle {
    precondition {
      condition     = local.ready
      error_message = "This precondition always fails."
    }
  }
}
