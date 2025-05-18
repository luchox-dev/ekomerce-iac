output "backend_instance_id" {
  description = "ID of the backend EC2 instance"
  value       = aws_instance.backend_instance.id
}

output "backend_instance_private_ip" {
  description = "Private IP address of the backend EC2 instance"
  value       = aws_instance.backend_instance.private_ip
}

output "backend_instance_public_ip" {
  description = "Public IP address of the backend EC2 instance"
  value       = aws_instance.backend_instance.public_ip
}

output "ubuntu_arm_ami_id" {
  description = "ID of the latest Ubuntu ARM AMI"
  value       = data.aws_ami.ubuntu_arm.id
}

output "ubuntu_amd64_ami_id" {
  description = "ID of the latest Ubuntu AMD64 AMI"
  value       = data.aws_ami.ubuntu.id
}