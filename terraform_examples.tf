# Examples of how to use the GitHub repository cloning script in Terraform

# Example 1: Using remote-exec provisioner to run the script on the backend instance
# COMMENTED OUT TO AVOID RESOURCE DUPLICATION - This is an example only
/*
resource "aws_instance" "example_backend" {
  # ... other instance configuration ...

  # Upload script to the instance
  provisioner "file" {
    source      = "${path.module}/scripts/github_repo_clone.py"
    destination = "/tmp/github_repo_clone.py"
  }

  # Upload SSH keys to the instance
  provisioner "file" {
    source      = "${path.module}/ssh_keys/"
    destination = "/tmp/ssh_keys/"
  }

  # Make script executable and run it
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/github_repo_clone.py",
      "sudo mkdir -p /opt/app",
      "sudo chown ubuntu:ubuntu /opt/app",
      "sudo -E python3 /tmp/github_repo_clone.py --ssh-dir /tmp/ssh_keys --dest-dir /opt/app"
    ]
  }

  # ... other provisioners ...
}
*/

# Example 2: Using the script as a module in the backend_instance resource in main.tf
# COMMENTED OUT TO AVOID RESOURCE DUPLICATION - This is an example only
/*
resource "aws_instance" "example_backend_instance" {
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

  # Shared connection block
  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = self.public_ip
    private_key = file("${path.module}/conn_keys/ec2-access.pem")
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install_node.sh"
    destination = "/tmp/install_node.sh"
  }

  # Add file provisioner for GitHub clone script
  provisioner "file" {
    source      = "${path.module}/scripts/github_repo_clone.py"
    destination = "/tmp/github_repo_clone.py"
  }

  # Add file provisioner for SSH keys directory
  provisioner "file" {
    source      = "${path.module}/ssh_keys/"
    destination = "/tmp/ssh_keys/"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update && sudo apt upgrade -y && sudo apt install -y curl build-essential python3 git",
      "chmod +x /tmp/install_node.sh && cd /tmp",
      "./install_node.sh 20",
      # Make GitHub clone script executable and run it
      "chmod +x /tmp/github_repo_clone.py",
      "sudo mkdir -p /opt/app",
      "sudo chown ubuntu:ubuntu /opt/app",
      "sudo -E python3 /tmp/github_repo_clone.py --ssh-dir /tmp/ssh_keys --dest-dir /opt/app",
      # Run letsencrypt script as final step
      "chmod +x /tmp/letsencrypt_wildcard_setup.py",
      "sudo python3 /tmp/letsencrypt_wildcard_setup.py"
    ]
  }
}
*/

# Example 3: Alternative approach using local-exec provisioner
# This example uses the local machine to generate an installation script
# that includes the SSH key and repository clone commands
# COMMENTED OUT TO AVOID RESOURCE DUPLICATION - This is an example only
/*
resource "aws_instance" "alternative_backend" {
  # ... other instance configuration ...

  # Using local-exec to generate a custom script
  provisioner "local-exec" {
    command = <<-EOT
      cat > ${path.module}/temp_deploy_script.sh <<'EOF'
      #!/bin/bash
      set -e

      # Create SSH directory
      mkdir -p ~/.ssh
      chmod 700 ~/.ssh

      # Add GitHub SSH key
      cat > ~/.ssh/github_key <<'KEYFILE'
      ${file("${path.module}/ssh_keys/github_key")}
      KEYFILE
      chmod 600 ~/.ssh/github_key

      # Add GitHub to known hosts
      ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts
      chmod 600 ~/.ssh/known_hosts

      # Configure SSH to use the key for GitHub
      cat > ~/.ssh/config <<'SSHCONFIG'
      Host github.com
        User git
        IdentityFile ~/.ssh/github_key
        StrictHostKeyChecking no
      SSHCONFIG
      chmod 600 ~/.ssh/config

      # Clone repository
      mkdir -p /opt/app
      git clone git@github.com:luchox-dev/qleber-platform.git /opt/app
      EOF
    EOT
  }

  # Upload the generated script
  provisioner "file" {
    source      = "${path.module}/temp_deploy_script.sh"
    destination = "/tmp/deploy_script.sh"
  }

  # Execute the script
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/deploy_script.sh",
      "sudo /tmp/deploy_script.sh"
    ]
  }

  # Clean up the temporary script locally
  provisioner "local-exec" {
    command = "rm -f ${path.module}/temp_deploy_script.sh"
  }
}
*/