# Planned against the state from applying `before/`, which declares the same
# resource.

terraform {
  # Keep in sync with `.config/mise.toml`•`lint-fixtures`•`tools`•`opentofu`:
  required_version = "~> 1.13.1"
}

resource "terraform_data" "example" {
  input = "example"
}
