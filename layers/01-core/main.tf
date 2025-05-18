terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "ekomerce-terraform-state-bucket"
    key            = "core/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ekomerce-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# Get the default VPC
data "aws_vpc" "default" {
  default = true
}

# Create a security group for inbound traffic
resource "aws_security_group" "common_sg" {
  name        = "common-sg"
  description = "Common security group for inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  # SSH access
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Consider restricting to trusted IPs
  }

  # HTTP access
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access
  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
    Name = "common-sg"
    Environment = var.environment
  }
}

# Store Elastic IP allocations
data "aws_eip" "backend_eip" {
  filter {
    name   = "allocation-id"
    values = ["eipalloc-0380b3818a8cbfdcf"]  # Backend EIP: 52.55.41.117
  }
}

data "aws_eip" "redis_eip" {
  filter {
    name   = "allocation-id"
    values = ["eipalloc-08972f8b220adedf5"]  # Redis EIP: 52.20.29.206
  }
}

data "aws_eip" "meilisearch_eip" {
  filter {
    name   = "allocation-id"
    values = ["eipalloc-088151e27b66250bc"]  # Meilisearch EIP: 44.205.227.56
  }
}