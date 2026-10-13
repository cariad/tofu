# Enough resources that the plan's text is longer than a PR comment can hold.

terraform {
  # Keep in sync with `.config/mise.toml`•`lint-fixtures`•`tools`•`opentofu`:
  required_version = "~> 1.13.1"
}

resource "terraform_data" "example" {
  count = 400

  input = "example"
}
