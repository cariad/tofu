# `sensitive-a/` and `sensitive-b/` differ only in this sensitive value.

terraform {
  # Keep in sync with `.config/mise.toml`•`lint-fixtures`•`tools`•`opentofu`:
  required_version = "~> 1.13.1"
}

resource "terraform_data" "example" {
  input = sensitive("example-a")
}
