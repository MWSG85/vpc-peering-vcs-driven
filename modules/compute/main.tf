data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Bastion / public instance in public subnet 1
resource "aws_instance" "public" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [var.public_sg_id]
  key_name               = var.key_name

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  tags = { Name = "${var.name}-public-ec2" }
}

# One private instance per private subnet (3 AZs)
resource "aws_instance" "private" {
  count                  = length(var.private_subnet_ids)
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[count.index]
  vpc_security_group_ids = [var.private_sg_id]
  key_name               = var.key_name

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "${var.name}-private-ec2-${count.index + 1}" }
}
