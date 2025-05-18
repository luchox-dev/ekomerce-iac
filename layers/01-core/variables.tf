variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  default     = "dev"
}

variable "key_name" {
  description = "SSH key name for EC2 instances"
  default     = "ec2-access"
}