output "public_instance_id" {
  value = aws_instance.public.id
}

output "public_ip" {
  value = aws_instance.public.public_ip
}

output "public_private_ip" {
  value = aws_instance.public.private_ip
}

output "private_ips" {
  value = aws_instance.private[*].private_ip
}
