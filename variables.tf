variable "key_name" {
  description = "SSH key name for EC2 instances"
}

variable "aws_region" {
  description = "AWS region to deploy resources"
}

variable "private_ip" {
  description = "Private IP address for Redis binding (e.g., 10.0.1.5)"
}

variable "redis_username" {
  description = "Redis ACL username (e.g., 'admin')"
}

variable "redis_password" {
  description = "Redis ACL password"
}

variable "meilisearch_master_key" {
  description = "Master key for Meilisearch instance"
  sensitive   = true
}