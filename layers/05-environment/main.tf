terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "ekomerce-terraform-state-bucket"
    key            = "environment/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ekomerce-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# Define remote state references for all layers
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

data "terraform_remote_state" "database" {
  backend = "s3"
  config = {
    bucket         = "ekomerce-terraform-state-bucket"
    key            = "database/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ekomerce-terraform-locks"
    encrypt        = true
  }
}

data "terraform_remote_state" "application" {
  backend = "s3"
  config = {
    bucket         = "ekomerce-terraform-state-bucket"
    key            = "application/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ekomerce-terraform-locks"
    encrypt        = true
  }
}

# Environment configuration provisioner
resource "null_resource" "environment_setup" {
  # Trigger on any changes to environment variables
  triggers = {
    env_version = var.environment_version
    environment = var.environment
  }

  # Connection settings for the backend instance
  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = data.terraform_remote_state.core.outputs.backend_eip_public_ip
    private_key = file("${path.module}/../../conn_keys/ec2-access.pem")
  }

  # Create environment file based on the current workspace
  provisioner "file" {
    content     = templatefile("${path.module}/templates/env.${var.environment}.tpl", {
      environment             = var.environment
      redis_endpoint          = data.terraform_remote_state.database.outputs.redis_endpoint
      redis_username          = var.redis_username
      redis_password          = var.redis_password
      meilisearch_endpoint    = data.terraform_remote_state.database.outputs.meilisearch_endpoint
      meilisearch_master_key  = var.meilisearch_master_key
      github_repo             = var.github_repo
    })
    destination = "/tmp/.env.${var.environment}"
  }

  # Apply environment-specific configuration
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /opt/app/config",
      "sudo mv /tmp/.env.${var.environment} /opt/app/.env.${var.environment}",
      "sudo ln -sf /opt/app/.env.${var.environment} /opt/app/.env",
      "echo 'Environment ${var.environment} configured at $(date)' | sudo tee -a /opt/app/config/environment_info.txt"
    ]
  }
}