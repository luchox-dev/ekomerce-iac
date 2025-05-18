output "environment" {
  description = "Active environment"
  value       = var.environment
}

output "environment_version" {
  description = "Version of the environment configuration"
  value       = var.environment_version
}

output "backend_endpoint" {
  description = "Backend API endpoint"
  value       = data.terraform_remote_state.application.outputs.backend_endpoint
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = data.terraform_remote_state.application.outputs.redis_endpoint
}

output "meilisearch_endpoint" {
  description = "Meilisearch endpoint"
  value       = data.terraform_remote_state.application.outputs.meilisearch_endpoint
}