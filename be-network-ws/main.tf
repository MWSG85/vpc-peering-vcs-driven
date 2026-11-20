module "network" {
  source = "../modules/network"

  name               = "backend"
  vpc_cidr           = var.vpc_cidr
  az_count           = 3
  enable_nat_gateway = var.enable_nat_gateway
}
