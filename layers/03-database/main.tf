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
    dynamodb_table = "ekomerce-terraform-locks"
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
    dynamodb_table = "ekomerce-terraform-locks"
    encrypt        = true
  }
}

# Reference compute layer for AMI information
data "terraform_remote_state" "compute" {
  backend = "s3"
  config = {
    bucket         = "ekomerce-terraform-state-bucket"
    key            = "compute/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ekomerce-terraform-locks"
    encrypt        = true
  }
}