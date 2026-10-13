# Planned against the state from applying `before/`.

terraform {
  # Keep in sync with `.config/mise.toml`•`lint-fixtures`•`tools`•`opentofu`:
  required_version = "~> 1.13.1"
}

resource "terraform_data" "new" {
  input = "example"
}

moved {
  from = terraform_data.old
  to   = terraform_data.new
}
