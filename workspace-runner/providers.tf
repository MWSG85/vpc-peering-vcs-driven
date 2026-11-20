terraform {
  required_version = ">= 1.6.0"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = ">= 0.62.0"
    }
  }
}

# Auth: set TFE_TOKEN (sensitive env var) on the workspace-runner workspace.
provider "tfe" {
  organization = var.tfc_organization
}
