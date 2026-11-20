# Security groups inside ONE VPC.
# Cross-VPC rules (frontend <-> backend) live in the vpc-peering workspace,
# because they need both VPCs and the peering connection to exist first.

# ---------- Public SG (bastion / jump host) ----------
resource "aws_security_group" "public" {
  name        = "${var.name}-public-sg"
  description = "Public instances in ${var.name} VPC"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-public-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "public_ssh" {
  security_group_id = aws_security_group.public.id
  description       = "SSH from admin IP only"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.admin_cidr
}

resource "aws_vpc_security_group_ingress_rule" "public_icmp_vpc" {
  security_group_id = aws_security_group.public.id
  description       = "Ping from inside the VPC"
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "public_all" {
  security_group_id = aws_security_group.public.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------- Private SG (app instances) ----------
resource "aws_security_group" "private" {
  name        = "${var.name}-private-sg"
  description = "Private instances in ${var.name} VPC"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-private-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "private_ssh_from_public" {
  security_group_id            = aws_security_group.private.id
  description                  = "SSH from the public (bastion) SG"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.public.id
}

resource "aws_vpc_security_group_ingress_rule" "private_icmp_vpc" {
  security_group_id = aws_security_group.private.id
  description       = "Ping from inside the VPC"
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "private_all" {
  security_group_id = aws_security_group.private.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
