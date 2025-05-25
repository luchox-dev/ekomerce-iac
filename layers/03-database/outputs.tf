output "redis_instance_id" {
  description = "ID of the Redis EC2 instance"
  value       = aws_instance.redis_instance.id
}

output "redis_instance_private_ip" {
  description = "Private IP address of the Redis instance"
  value       = aws_instance.redis_instance.private_ip
}

output "redis_instance_public_ip" {
  description = "Public IP address of the Redis instance"
  value       = data.terraform_remote_state.core.outputs.redis_eip_public_ip
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = "${data.terraform_remote_state.core.outputs.redis_eip_public_ip}:6379"
}

output "meilisearch_instance_id" {
  description = "ID of the Meilisearch EC2 instance"
  value       = aws_instance.meilisearch_instance.id
}

output "meilisearch_instance_private_ip" {
  description = "Private IP address of the Meilisearch instance"
  value       = aws_instance.meilisearch_instance.private_ip
}

output "meilisearch_instance_public_ip" {
  description = "Public IP address of the Meilisearch instance"
  value       = data.terraform_remote_state.core.outputs.meilisearch_eip_public_ip
}

output "meilisearch_endpoint" {
  description = "Meilisearch API endpoint URL"
  value       = "http://${data.terraform_remote_state.core.outputs.meilisearch_eip_public_ip}:7700"
}