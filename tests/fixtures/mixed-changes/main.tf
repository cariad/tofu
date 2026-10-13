# Planned against the state from applying `before/`. `terraform_data.deleted`
# is only declared there, so this plan deletes it.

terraform {
  # Keep in sync with `.config/mise.toml`•`lint-fixtures`•`tools`•`opentofu`:
  required_version = "~> 1.13.1"
}

resource "terraform_data" "created" {
  input = "example"
}

resource "terraform_data" "updated" {
  input = "after"
}

output "example" {
  value = "example"
}
