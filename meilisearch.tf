# Using the existing Ubuntu ARM AMI data source from main.tf

# Create a security group for Meilisearch
resource "aws_security_group" "meilisearch_sg" {
  name        = "meilisearch-sg"
  description = "Security group for Meilisearch instance"
  vpc_id      = data.aws_vpc.default.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Consider restricting to trusted IPs
  }

  # Meilisearch port access - restrict to backend EIP only
  ingress {
    description = "Meilisearch API"
    from_port   = 7700
    to_port     = 7700
    protocol    = "tcp"
    cidr_blocks = ["${data.aws_eip.backend_eip.public_ip}/32"]  # Allow access from the backend IP
  }

  # Egress rule to allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Prepare user data script with the master key and allowed IP
locals {
  meilisearch_user_data = templatefile("${path.module}/meilisearch_userdata.sh", {
    master_key = var.meilisearch_master_key
    allowed_ip = data.aws_eip.backend_eip.public_ip
  })
  
  # Log the generated script for debugging (without sensitive info)
  # This is optional but helps in troubleshooting
  debug_user_data = replace(
    replace(
      local.meilisearch_user_data,
      var.meilisearch_master_key,
      "REDACTED_MASTER_KEY"
    ),
    data.aws_eip.backend_eip.public_ip,
    "ALLOWED_IP"
  )
}

# Create the EC2 instance for Meilisearch
resource "aws_instance" "meilisearch_instance" {
  ami           = data.aws_ami.ubuntu_arm.id
  instance_type = "t4g.micro"
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.meilisearch_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }

  tags = {
    Name = "meilisearch-instance"
  }

  # Shared connection block
  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = self.public_ip
    private_key = file("${path.module}/conn_keys/ec2-access.pem")
  }

  user_data = local.meilisearch_user_data
}

# Associate the dedicated Elastic IP with the Meilisearch instance
resource "aws_eip_association" "meilisearch_association" {
  instance_id   = aws_instance.meilisearch_instance.id
  allocation_id = "eipalloc-088151e27b66250bc"  # Meilisearch Elastic IP: 44.205.227.56
}

# Data source to look up the Meilisearch instance's Elastic IP
data "aws_eip" "meilisearch_eip" {
  filter {
    name   = "allocation-id"
    values = ["eipalloc-088151e27b66250bc"]
  }
}

# Output the Meilisearch instance information
output "meilisearch_instance_ip" {
  value = data.aws_eip.meilisearch_eip.public_ip
}

output "meilisearch_endpoint" {
  value = "http://${data.aws_eip.meilisearch_eip.public_ip}:7700"
}

output "meilisearch_master_key" {
  value     = var.meilisearch_master_key
  sensitive = true
}