# These outputs are read by the security, compute and vpc-peering workspaces
output "vpc_id" {
  value = module.network.vpc_id
}

output "vpc_cidr" {
  value = module.network.vpc_cidr
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "public_route_table_id" {
  value = module.network.public_route_table_id
}

output "private_route_table_ids" {
  value = module.network.private_route_table_ids
}
