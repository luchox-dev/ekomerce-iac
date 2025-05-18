variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  default     = "dev"
}

variable "environment_version" {
  description = "Version of the environment configuration"
  default     = "1.0.0"
}

variable "redis_username" {
  description = "Redis ACL username"
  default     = "backend"
}

variable "redis_password" {
  description = "Redis ACL password"
  sensitive   = true
}

variable "meilisearch_master_key" {
  description = "Master key for Meilisearch instance"
  sensitive   = true
}

variable "github_repo" {
  description = "GitHub repository to clone"
  default     = "git@github.com:luchox-dev/qleber-platform.git"
}