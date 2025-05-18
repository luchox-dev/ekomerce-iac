output "vpc_id" {
  description = "ID of the default VPC"
  value       = data.aws_vpc.default.id
}

output "common_sg_id" {
  description = "ID of the common security group"
  value       = aws_security_group.common_sg.id
}

output "backend_eip_public_ip" {
  description = "Public IP of the backend Elastic IP"
  value       = data.aws_eip.backend_eip.public_ip
}

output "redis_eip_public_ip" {
  description = "Public IP of the Redis Elastic IP"
  value       = data.aws_eip.redis_eip.public_ip
}

output "meilisearch_eip_public_ip" {
  description = "Public IP of the Meilisearch Elastic IP"
  value       = data.aws_eip.meilisearch_eip.public_ip
}

output "backend_eip_allocation_id" {
  description = "Allocation ID of the backend Elastic IP"
  value       = data.aws_eip.backend_eip.id
}

output "redis_eip_allocation_id" {
  description = "Allocation ID of the Redis Elastic IP"
  value       = data.aws_eip.redis_eip.id
}

output "meilisearch_eip_allocation_id" {
  description = "Allocation ID of the Meilisearch Elastic IP"
  value       = data.aws_eip.meilisearch_eip.id
}

output "aws_region" {
  description = "AWS region used for deployment"
  value       = var.aws_region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "key_name" {
  description = "SSH key name for EC2 instances"
  value       = var.key_name
}