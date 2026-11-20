data "terraform_remote_state" "network" {
  backend = "remote"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = "fe-network-ws"
    }
  }
}

data "terraform_remote_state" "security" {
  backend = "remote"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = "fe-security-ws"
    }
  }
}

module "compute" {
  source = "../modules/compute"

  name               = "frontend"
  instance_type      = var.instance_type
  key_name           = var.key_name
  public_subnet_ids  = data.terraform_remote_state.network.outputs.public_subnet_ids
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  public_sg_id       = data.terraform_remote_state.security.outputs.public_sg_id
  private_sg_id      = data.terraform_remote_state.security.outputs.private_sg_id
}
