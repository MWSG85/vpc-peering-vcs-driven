output "bastion_public_ip" {
  value = module.compute.public_ip
}

output "private_ips" {
  value = module.compute.private_ips
}
