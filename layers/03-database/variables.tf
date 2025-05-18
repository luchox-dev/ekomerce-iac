variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  default     = "dev"
}

variable "private_ip" {
  description = "Private IP address for Redis binding (e.g., 10.0.1.5)"
  default     = "0.0.0.0"
}

variable "redis_username" {
  description = "Redis ACL username (e.g., 'admin')"
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