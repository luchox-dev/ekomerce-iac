terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "ekomerce-terraform-state-bucket"
    key            = "database/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# Reference core layer for network information
data "terraform_remote_state" "core" {
  backend = "s3"
  config = {
    bucket         = "ekomerce-terraform-state-bucket"
    key            = "core/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
  workspace = terraform.workspace
}

# Reference compute layer for AMI information
data "terraform_remote_state" "compute" {
  backend = "s3"
  config = {
    bucket         = "ekomerce-terraform-state-bucket"
    key            = "compute/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
  workspace = terraform.workspace
}

# Look up the latest official Ubuntu 24.04 AMI for AMD64
data "aws_ami" "ubuntu_amd64" {
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

# Look up the latest official Ubuntu 24.04 AMI for ARM64
data "aws_ami" "ubuntu_arm64" {
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