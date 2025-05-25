terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "ekomerce-terraform-state-bucket"
    key            = "application/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# Reference core layer for network information
data "terraform_remote_state" "core" {
  backend = "s3"
  config = {
    bucket         = "ekomerce-terraform-state-bucket"
    key            = "core/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
  workspace = terraform.workspace
}

# Reference compute layer for EC2 instances
data "terraform_remote_state" "compute" {
  backend = "s3"
  config = {
    bucket         = "ekomerce-terraform-state-bucket"
    key            = "compute/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
  workspace = terraform.workspace
}

# Reference database layer for DB instances
data "terraform_remote_state" "database" {
  backend = "s3"
  config = {
    bucket         = "ekomerce-terraform-state-bucket"
    key            = "database/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
  workspace = terraform.workspace
}

# Define null_resource for local-only modifications and provisioners
resource "null_resource" "backend_provisioner" {
  # Trigger on instance ID or any script change
  triggers = {
    instance_id = data.terraform_remote_state.compute.outputs.backend_instance_id
    scripts_hash = sha256(join("", [
      filesha256("${path.module}/../../scripts/install_node.sh"),
      filesha256("${path.module}/../../scripts/github_repo_clone.py"),
      filesha256("${path.module}/../../scripts/letsencrypt_wildcard_setup.py")
    ]))
  }

  # Connection settings for the backend instance
  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = data.terraform_remote_state.core.outputs.backend_eip_public_ip
    private_key = file("${path.module}/../../conn_keys/ec2-access.pem")
  }  

  provisioner "file" {
    source      = "${path.module}/../../scripts/install_node.sh"
    destination = "/tmp/install_node.sh"
  }

  provisioner "file" {
    source      = "${path.module}/../../scripts/github_repo_clone.py"
    destination = "/tmp/github_repo_clone.py"
  }

  provisioner "file" {
    source      = "${path.module}/../../scripts/letsencrypt_wildcard_setup.py"
    destination = "/tmp/letsencrypt_wildcard_setup.py"
  }

  provisioner "file" {
    source      = "${path.module}/../../ssh_keys/id_ec2_ed25519"
    destination = "/home/ubuntu/id_ec2_ed25519"
  }

  provisioner "file" {
    source      = "${path.module}/../../ssh_keys/id_ec2_ed25519.pub"
    destination = "/home/ubuntu/id_ec2_ed25519.pub"
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
      "sudo -E python3 /tmp/github_repo_clone.py --ssh-dir /home/ubuntu/ssh_keys --dest-dir /opt/app --repo ${var.github_repo}"
    ]
  }

}

# Redis provisioner
resource "null_resource" "redis_provisioner" {
  # Trigger on instance ID or script changes
  triggers = {
    instance_id = data.terraform_remote_state.database.outputs.redis_instance_id
    script_hash = filesha256("${path.module}/../../scripts/install_redis_on_ubuntu24.04.sh")
  }

  # Connection settings for the Redis instance
  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = data.terraform_remote_state.core.outputs.redis_eip_public_ip  # Using actual public IP
    private_key = file("${path.module}/../../conn_keys/ec2-access.pem")
    timeout     = "5m"  # Increased timeout for SSH connection
    agent       = false # Disable agent forwarding
  }

  # Upload Redis installation script
  provisioner "file" {
    source      = "${path.module}/../../scripts/install_redis_on_ubuntu24.04.sh"
    destination = "/tmp/install_redis_on_ubuntu24.04.sh"
  }

  # Execute Redis installation
  provisioner "remote-exec" {
    inline = [
      "export PRIVATE_IP=0.0.0.0",  # Using actual private IP
      "export REDIS_USERNAME=${var.redis_username}",
      "export REDIS_PASSWORD=${var.redis_password}",
      "export ALLOWED_IP=${data.terraform_remote_state.core.outputs.backend_eip_public_ip}",  # Using actual public IP
      "sudo apt update && sudo apt upgrade -y",
      "chmod +x /tmp/install_redis_on_ubuntu24.04.sh",
      "sudo -E /tmp/install_redis_on_ubuntu24.04.sh"
    ]
  }

  # Depends on backend provisioner to ensure correct IP configuration
  depends_on = [null_resource.backend_provisioner]
}