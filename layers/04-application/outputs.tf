output "backend_endpoint" {
  description = "Public endpoint of the backend application"
  value       = "https://api.qleber.co"
}

output "redis_endpoint" {
  description = "Redis endpoint for application"
  value       = data.terraform_remote_state.database.outputs.redis_endpoint
}

output "meilisearch_endpoint" {
  description = "Meilisearch API endpoint"
  value       = data.terraform_remote_state.database.outputs.meilisearch_endpoint
}