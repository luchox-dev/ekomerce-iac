# Create Redis security group
resource "aws_security_group" "redis_sg" {
  name        = "redis-sg"
  description = "Rules for Redis inbound traffic"
  vpc_id      = data.terraform_remote_state.core.outputs.vpc_id

  # Existing ingress rule for SSH access is in the common SG

  # Redis access
  ingress {
    description = "Redis"
    from_port   = 6379
    to_port     = 6379
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
    Name        = "redis-sg"
    Environment = var.environment
  }
}

# Create an EC2 instance with 40GB of general purpose storage for Redis
resource "aws_instance" "redis_instance" {
  ami           = data.terraform_remote_state.compute.outputs.ubuntu_amd64_ami_id
  instance_type = "t2.micro"
  key_name      = data.terraform_remote_state.core.outputs.key_name

  vpc_security_group_ids = [
    data.terraform_remote_state.core.outputs.common_sg_id,
    aws_security_group.redis_sg.id
  ]

  root_block_device {
    volume_size = 40
    volume_type = "gp2"
  }

  tags = {
    Name        = "redis-instance"
    Environment = var.environment
  }

  # The provisioner will be in the application layer
}

# Associate the pre-allocated Elastic IP with the Redis instance
resource "aws_eip_association" "redis_association" {
  instance_id   = aws_instance.redis_instance.id
  allocation_id = data.terraform_remote_state.core.outputs.redis_eip_allocation_id
}