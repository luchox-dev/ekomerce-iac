terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "ekomerce-terraform-state-bucket"  # Must match your created bucket name
    key            = "terraform.tfstate"
    region         = "us-east-1"                        # Must match your selected region
    dynamodb_table = "ekomerce-terraform-locks"         # Must match your created DynamoDB table
    encrypt        = true                               # Ensures the state file is encrypted at rest
  }
}

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

provider "aws" {
  region = var.aws_region
}

# Look up the latest official Ubuntu 22.04 AMI from Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical's owner ID for Ubuntu AMIs

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get the default VPC (needed to associate the security group)
data "aws_vpc" "default" {
  default = true
}

# Create a security group to allow SSH access
resource "aws_security_group" "redis-sg" {
  name        = "redis-sg"
  description = "Rules for inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  # Existing ingress rule for SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Consider restricting to trusted IPs
  }

  # New ingress rule for Redis access
  ingress {
    description = "Redis"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["${data.aws_eip.backend_eip.public_ip}/32"]  # Replace with your trusted IP or CIDR block if needed
  }

  # Egress rule to allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an EC2 instance with 40GB of general purpose storage for Redis
resource "aws_instance" "redis_instance" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.redis-sg.id]

  root_block_device {
    volume_size = 40
    volume_type = "gp2"
  }

  tags = {
    Name = "redis-instance"
  }

  # ✅ Shared connection block
  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = self.public_ip
    private_key = file("${path.module}/conn_keys/ec2-access.pem")
  }

  provisioner "file" {
    source      = "${path.module}/install_redis_on_ubunut24.04.sh"
    destination = "/tmp/install_redis_on_ubunut24.04.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "export PRIVATE_IP=${var.private_ip}",
      "export REDIS_USERNAME=${var.redis_username}",
      "export REDIS_PASSWORD=${var.redis_password}",
      "export ALLOWED_IP=${data.aws_eip.backend_eip.public_ip}",
      "sudo apt update && sudo apt upgrade -y",
      "chmod +x /tmp/install_redis_on_ubunut24.04.sh",
      "sudo -E /tmp/install_redis_on_ubunut24.04.sh"
    ]
  }

  depends_on = [aws_eip_association.backend_association]
}


# Look up the latest official Ubuntu 24.04 AMI for ARM architecture from Canonical
data "aws_ami" "ubuntu_arm" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical's owner ID for Ubuntu AMIs

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# Create a security group to allow SSH and HTTP access
resource "aws_security_group" "backend_sg" {
  name        = "backend-sg"
  description = "Security group for backend instance"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create the backend EC2 instance with 20GB of general-purpose storage
resource "aws_instance" "backend_instance" {
  ami           = data.aws_ami.ubuntu_arm.id
  instance_type = "t4g.micro"
  key_name      = var.key_name

  # Use the security group to allow SSH and HTTP access
  vpc_security_group_ids = [aws_security_group.backend_sg.id]

  # Configure the root block device with 20GB gp2 storage
  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }

  tags = {
    Name = "ekomerce-backend"
  }

  # ✅ Shared connection block
  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = self.public_ip
    private_key = file("${path.module}/conn_keys/ec2-access.pem")
  }

  provisioner "file" {
    source      = "${path.module}/install_node.sh"
    destination = "/tmp/install_node.sh"
  }

  provisioner "file" {
    source      = "${path.module}/.certs"
    destination = "/tmp/"
  }

  provisioner "file" {
    source      = "${path.module}/letsencrypt_wildcard_setup.py"
    destination = "/tmp/letsencrypt_wildcard_setup.py"
  }

  # Add file provisioner for SSH keys
  provisioner "file" {
    source      = "${path.module}/ssh_keys/id_ec2_ed25519"
    destination = "/home/ubuntu/id_ec2_ed25519"
  }

  provisioner "file" {
    source      = "${path.module}/ssh_keys/id_ec2_ed25519.pub"
    destination = "/home/ubuntu/id_ec2_ed25519.pub"
  }

  # Add file provisioner for GitHub clone script
  provisioner "file" {
    source      = "${path.module}/github_repo_clone.py"
    destination = "/tmp/github_repo_clone.py"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update && sudo apt upgrade -y && sudo apt install -y curl build-essential certbot python3-certbot-nginx git",
      "chmod +x /tmp/install_node.sh && cd /tmp",
      "./install_node.sh 20",
      
      # Setup SSH keys with proper permissions and start SSH agent
      "mkdir -p /home/ubuntu/ssh_keys",
      "mv /home/ubuntu/id_ec2_ed25519 /home/ubuntu/ssh_keys/",
      "mv /home/ubuntu/id_ec2_ed25519.pub /home/ubuntu/ssh_keys/",
      "chmod 600 /home/ubuntu/ssh_keys/id_ec2_ed25519",
      "chmod 644 /home/ubuntu/ssh_keys/id_ec2_ed25519.pub",
      "eval $(ssh-agent) && ssh-add /home/ubuntu/ssh_keys/id_ec2_ed25519",
      
      # Execute LetsEncrypt setup
      "chmod +x /tmp/letsencrypt_wildcard_setup.py",
      "sudo python3 /tmp/letsencrypt_wildcard_setup.py",
      
      # Clone GitHub repository with no prompt for host key verification
      "chmod +x /tmp/github_repo_clone.py",
      "sudo mkdir -p /opt/app",
      "sudo chown ubuntu:ubuntu /opt/app",
      "ssh-keyscan -t rsa,ecdsa,ed25519 github.com | sudo tee -a /etc/ssh/ssh_known_hosts",
      "export GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes'",
      "sudo -E python3 /tmp/github_repo_clone.py --ssh-dir /home/ubuntu/ssh_keys --dest-dir /opt/app --repo git@github.com:luchox-dev/qleber-platform.git"
    ]
  }
}

# Associate the pre-allocated Elastic IP with the Redis instance
resource "aws_eip_association" "redis_association" {
  instance_id   = aws_instance.redis_instance.id
  allocation_id = "eipalloc-08972f8b220adedf5"  # Elastic IP: 52.20.29.206
}

# Associate the pre-allocated Elastic IP with the backend (app) instance
resource "aws_eip_association" "backend_association" {
  instance_id   = aws_instance.backend_instance.id
  allocation_id = "eipalloc-0380b3818a8cbfdcf"  # Elastic IP: 52.55.41.117
}

# Data source to look up the backend instance's Elastic IP
data "aws_eip" "backend_eip" {
  filter {
    name   = "allocation-id"
    values = ["eipalloc-0380b3818a8cbfdcf"]  # Replace with your EIP's allocation ID
  }
}
