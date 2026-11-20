data "terraform_remote_state" "fe_network" {
  backend = "remote"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = "fe-network-ws"
    }
  }
}

data "terraform_remote_state" "be_network" {
  backend = "remote"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = "be-network-ws"
    }
  }
}

data "terraform_remote_state" "fe_security" {
  backend = "remote"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = "fe-security-ws"
    }
  }
}

data "terraform_remote_state" "be_security" {
  backend = "remote"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = "be-security-ws"
    }
  }
}

locals {
  fe = data.terraform_remote_state.fe_network.outputs
  be = data.terraform_remote_state.be_network.outputs

  fe_sg = data.terraform_remote_state.fe_security.outputs
  be_sg = data.terraform_remote_state.be_security.outputs

  # All route tables in each VPC (public + 3 private)
  fe_route_tables = concat([local.fe.public_route_table_id], local.fe.private_route_table_ids)
  be_route_tables = concat([local.be.public_route_table_id], local.be.private_route_table_ids)
}

# ---------- Peering (same account + same region => auto_accept) ----------
resource "aws_vpc_peering_connection" "fe_be" {
  vpc_id      = local.fe.vpc_id
  peer_vpc_id = local.be.vpc_id
  auto_accept = true

  tags = { Name = "frontend-to-backend-peering" }
}

# ---------- Routes: frontend -> backend ----------
resource "aws_route" "fe_to_be" {
  count                     = length(local.fe_route_tables)
  route_table_id            = local.fe_route_tables[count.index]
  destination_cidr_block    = local.be.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.fe_be.id
}

# ---------- Routes: backend -> frontend ----------
resource "aws_route" "be_to_fe" {
  count                     = length(local.be_route_tables)
  route_table_id            = local.be_route_tables[count.index]
  destination_cidr_block    = local.fe.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.fe_be.id
}

# ---------- Shared security rules (need BOTH VPCs, so they live here) ----------
# Backend private SG allows the app port from the frontend private SG
resource "aws_vpc_security_group_ingress_rule" "be_app_from_fe" {
  security_group_id            = local.be_sg.private_sg_id
  description                  = "App traffic from frontend private SG"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = local.fe_sg.private_sg_id

  depends_on = [aws_vpc_peering_connection.fe_be]
}

# Ping between frontend and backend private instances (for testing)
resource "aws_vpc_security_group_ingress_rule" "be_icmp_from_fe" {
  security_group_id            = local.be_sg.private_sg_id
  description                  = "Ping from frontend private SG"
  ip_protocol                  = "icmp"
  from_port                    = -1
  to_port                      = -1
  referenced_security_group_id = local.fe_sg.private_sg_id

  depends_on = [aws_vpc_peering_connection.fe_be]
}

resource "aws_vpc_security_group_ingress_rule" "fe_icmp_from_be" {
  security_group_id            = local.fe_sg.private_sg_id
  description                  = "Ping from backend private SG"
  ip_protocol                  = "icmp"
  from_port                    = -1
  to_port                      = -1
  referenced_security_group_id = local.be_sg.private_sg_id

  depends_on = [aws_vpc_peering_connection.fe_be]
}
