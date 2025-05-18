terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "ekomerce-terraform-state-bucket"
    key            = "compute/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ekomerce-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# Reference data from core layer
data "terraform_remote_state" "core" {
  backend = "s3"
  config = {
    bucket         = "ekomerce-terraform-state-bucket"
    key            = "core/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ekomerce-terraform-locks"
    encrypt        = true
  }
}

# Look up the latest official Ubuntu 24.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical's owner ID for Ubuntu AMIs

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Look up the latest official Ubuntu 24.04 AMI for ARM architecture
data "aws_ami" "ubuntu_arm" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical's owner ID for Ubuntu AMIs

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# Create a security group for backend instance
resource "aws_security_group" "backend_sg" {
  name        = "backend-sg"
  description = "Security group for backend instance"
  vpc_id      = data.terraform_remote_state.core.outputs.vpc_id

  # All ingress rules are defined in the common SG from core layer
  # This SG is for instance-specific rules

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "backend-sg"
    Environment = var.environment
  }
}

# Create the backend EC2 instance with 20GB of general-purpose storage
resource "aws_instance" "backend_instance" {
  ami           = data.aws_ami.ubuntu_arm.id
  instance_type = "t4g.micro"
  key_name      = data.terraform_remote_state.core.outputs.key_name

  # Use both security groups
  vpc_security_group_ids = [
    data.terraform_remote_state.core.outputs.common_sg_id,
    aws_security_group.backend_sg.id
  ]

  # Configure the root block device with 20GB gp2 storage
  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }

  tags = {
    Name        = "ekomerce-backend"
    Environment = var.environment
  }

  # Do not include provisioners here - they will be in the application layer
}

# Associate the pre-allocated Elastic IP with the backend instance
resource "aws_eip_association" "backend_association" {
  instance_id   = aws_instance.backend_instance.id
  allocation_id = data.terraform_remote_state.core.outputs.backend_eip_allocation_id
}