# Create a security group for Meilisearch
resource "aws_security_group" "meilisearch_sg" {
  name        = "meilisearch-sg"
  description = "Security group for Meilisearch instance"
  vpc_id      = data.terraform_remote_state.core.outputs.vpc_id

  # SSH access is in the common SG

  # Meilisearch port access - restrict to backend EIP only
  ingress {
    description = "Meilisearch API"
    from_port   = 7700
    to_port     = 7700
    protocol    = "tcp"
    cidr_blocks = ["${data.terraform_remote_state.core.outputs.backend_eip_public_ip}/32"]
  }

  # Egress rule to allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "meilisearch-sg"
    Environment = var.environment
  }
}

# Prepare user data script with the master key and allowed IP
locals {
  meilisearch_user_data = templatefile("${path.module}/../../scripts/meilisearch_userdata.sh", {
    master_key = var.meilisearch_master_key
    allowed_ip = data.terraform_remote_state.core.outputs.backend_eip_public_ip
  })
}

# Create the EC2 instance for Meilisearch
resource "aws_instance" "meilisearch_instance" {
  ami           = data.aws_ami.ubuntu_arm64.id
  instance_type = "t4g.micro"
  key_name      = data.terraform_remote_state.core.outputs.key_name

  vpc_security_group_ids = [
    data.terraform_remote_state.core.outputs.common_sg_id,
    aws_security_group.meilisearch_sg.id
  ]

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }

  tags = {
    Name        = "meilisearch-instance"
    Environment = var.environment
  }

  user_data = local.meilisearch_user_data
}

# Associate the dedicated Elastic IP with the Meilisearch instance
resource "aws_eip_association" "meilisearch_association" {
  instance_id   = aws_instance.meilisearch_instance.id
  allocation_id = data.terraform_remote_state.core.outputs.meilisearch_eip_allocation_id
}