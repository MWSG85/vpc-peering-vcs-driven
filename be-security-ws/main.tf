data "terraform_remote_state" "network" {
  backend = "remote"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = "be-network-ws"
    }
  }
}

module "security" {
  source = "../modules/security"

  name       = "backend"
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr   = data.terraform_remote_state.network.outputs.vpc_cidr
  admin_cidr = var.admin_cidr
}
