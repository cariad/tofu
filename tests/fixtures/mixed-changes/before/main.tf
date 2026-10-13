terraform {
  # Keep in sync with `.config/mise.toml`•`lint-fixtures`•`tools`•`opentofu`:
  required_version = "~> 1.13.1"
}

resource "terraform_data" "updated" {
  input = "before"
}

resource "terraform_data" "deleted" {
  input = "example"
}
