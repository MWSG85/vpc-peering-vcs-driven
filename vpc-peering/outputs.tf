output "peering_connection_id" {
  value = aws_vpc_peering_connection.fe_be.id
}

output "peering_status" {
  value = aws_vpc_peering_connection.fe_be.accept_status
}
