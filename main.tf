# DevOpsFoundry's root module is intentionally empty: the Terraform Registry
# requires a module at the repository root, but everything useful is a
# submodule. Call one of them instead, for example:
#
#   module "bucket" {
#     source  = "theJuddson/devopsfoundry/aws//modules/object-store"
#     version = "~> 1.2"
#   }
#
# See README.md for the full list.
terraform {
  required_version = ">= 1.7.0"
}
