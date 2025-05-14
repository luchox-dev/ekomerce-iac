# ARM-powered search: Deploying Meilisearch on EC2 with Terraform

This comprehensive guide walks you through deploying Meilisearch on an ARM-based Ubuntu EC2 instance using Terraform with IP-restricted access. By the end, you'll have a functioning Meilisearch instance running on a cost-effective t4g.micro instance in the us-east-1 region.

**Meilisearch provides lightning-fast, typo-tolerant search functionality with minimal configuration.** This guide helps you deploy it securely on AWS's Graviton2 ARM processors, which offer better price-performance than comparable x86 instances. You'll learn how to restrict access to specific IPs, automate installation with Terraform, and follow best practices for production deployment.

## Prerequisites and setup

Before beginning, ensure you have:

1. AWS CLI installed and configured with appropriate permissions
2. Terraform (version 1.0+) installed
3. Basic knowledge of AWS services (EC2, VPC, Security Groups)
4. A list of IP addresses that should be allowed to access your Meilisearch instance

### Setting up Terraform

1. Create a new directory for your Terraform configuration:

```bash
mkdir meilisearch-terraform && cd meilisearch-terraform
```

2. Initialize Terraform in this directory:

```bash
terraform init
```

## Creating Terraform configuration files

You'll need three main files for this deployment:
- `variables.tf` - Defines customizable inputs
- `main.tf` - Contains the main infrastructure configuration
- `meilisearch_userdata.sh` - Contains the installation script

### 1. Creating variables.tf

Create a file named `variables.tf` with the following content:

```hcl
variable "AWS_REGION" {
  default = "us-east-1"
}

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}

variable "ssh_allowed_ips" {
  description = "IPs allowed to SSH to the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Replace with your IP address in production
}

variable "meilisearch_allowed_ips" {
  description = "IPs allowed to access Meilisearch API directly"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Replace with your IP address in production
}

variable "http_allowed_ips" {
  description = "IPs allowed to access HTTP"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Replace with your IP address in production
}

variable "https_allowed_ips" {
  description = "IPs allowed to access HTTPS"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Replace with your IP address in production
}
```

### 2. Creating main.tf

Create `main.tf` with the following configuration:

```hcl
provider "aws" {
  region = var.AWS_REGION
}

# Generate a random master key for Meilisearch
resource "random_password" "master_key" {
  length  = 32
  special = true
}

# Find the latest Ubuntu 22.04 ARM AMI
data "aws_ami" "ubuntu_arm" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Create a VPC for our instance
resource "aws_vpc" "meilisearch_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "meilisearch-vpc"
  }
}

# Create a subnet for our instance
resource "aws_subnet" "meilisearch_subnet" {
  vpc_id                  = aws_vpc.meilisearch_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.AWS_REGION}a"

  tags = {
    Name = "meilisearch-subnet"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "meilisearch_igw" {
  vpc_id = aws_vpc.meilisearch_vpc.id

  tags = {
    Name = "meilisearch-igw"
  }
}

# Create a route table
resource "aws_route_table" "meilisearch_route_table" {
  vpc_id = aws_vpc.meilisearch_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.meilisearch_igw.id
  }

  tags = {
    Name = "meilisearch-route-table"
  }
}

# Associate the route table with the subnet
resource "aws_route_table_association" "meilisearch_route_association" {
  subnet_id      = aws_subnet.meilisearch_subnet.id
  route_table_id = aws_route_table.meilisearch_route_table.id
}

# Create a security group for Meilisearch
resource "aws_security_group" "meilisearch_sg" {
  name        = "meilisearch-sg"
  description = "Security group for Meilisearch"
  vpc_id      = aws_vpc.meilisearch_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_ips
    description = "SSH access"
  }

  # Meilisearch port access
  ingress {
    from_port   = 7700
    to_port     = 7700
    protocol    = "tcp"
    cidr_blocks = var.meilisearch_allowed_ips
    description = "Meilisearch API access"
  }

  # HTTP access (for Nginx)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.http_allowed_ips
    description = "HTTP access"
  }

  # HTTPS access (for Nginx with SSL)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.https_allowed_ips
    description = "HTTPS access"
  }

  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "meilisearch-sg"
  }
}

# Create a key pair for SSH access
resource "aws_key_pair" "meilisearch_key" {
  key_name   = "meilisearch-key"
  public_key = var.ssh_public_key
}

# Prepare user data script with the master key
locals {
  user_data = templatefile("${path.module}/meilisearch_userdata.sh", {
    master_key = random_password.master_key.result
  })
}

# Create the EC2 instance
resource "aws_instance" "meilisearch" {
  ami                    = data.aws_ami.ubuntu_arm.id
  instance_type          = "t4g.micro"
  key_name               = aws_key_pair.meilisearch_key.key_name
  vpc_security_group_ids = [aws_security_group.meilisearch_sg.id]
  subnet_id              = aws_subnet.meilisearch_subnet.id
  user_data              = local.user_data

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "meilisearch-server"
  }

  credit_specification {
    cpu_credits = "unlimited"
  }
}

# Output important information
output "meilisearch_public_ip" {
  value = aws_instance.meilisearch.public_ip
}

output "meilisearch_dns" {
  value = aws_instance.meilisearch.public_dns
}

output "meilisearch_endpoint" {
  value = "http://${aws_instance.meilisearch.public_dns}:7700"
}

output "meilisearch_master_key" {
  value     = random_password.master_key.result
  sensitive = true
}
```

### 3. Creating meilisearch_userdata.sh

Create a file named `meilisearch_userdata.sh` with the following content:

```bash
#!/bin/bash

# Update system packages
apt-get update && apt-get upgrade -y

# Install required dependencies
apt-get install -y curl systemd

# Create a user for Meilisearch
useradd -d /var/lib/meilisearch -s /bin/false -m -r meilisearch

# Install Meilisearch using the official script
curl -L https://install.meilisearch.com | sh

# Move the binary to a standard location
mv ./meilisearch /usr/local/bin/

# Create directories for Meilisearch data
mkdir -p /var/lib/meilisearch/data /var/lib/meilisearch/dumps /var/lib/meilisearch/snapshots
chown -R meilisearch:meilisearch /var/lib/meilisearch
chmod 750 /var/lib/meilisearch

# Create config file
cat > /etc/meilisearch.toml << 'EOF'
# Meilisearch configuration file
env = "production"
master_key = "${master_key}"
db_path = "/var/lib/meilisearch/data"
dump_dir = "/var/lib/meilisearch/dumps"
snapshot_dir = "/var/lib/meilisearch/snapshots"
http_addr = "0.0.0.0:7700"
# Log level can be one of: OFF, ERROR, WARN, INFO, DEBUG, TRACE
log_level = "INFO"
# Max indexing memory limit - important for t4g.micro instances
max_indexing_memory = "1 GiB"
# Snapshot creation interval in seconds (86400 = 24 hours)
schedule_snapshot = 86400
EOF

# Create systemd service file
cat > /etc/systemd/system/meilisearch.service << 'EOF'
[Unit]
Description=Meilisearch
After=systemd-user-sessions.service

[Service]
Type=simple
WorkingDirectory=/var/lib/meilisearch
ExecStart=/usr/local/bin/meilisearch --config-file-path /etc/meilisearch.toml
User=meilisearch
Group=meilisearch
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Meilisearch service
systemctl daemon-reload
systemctl enable meilisearch
systemctl start meilisearch
```

### 4. Creating terraform.tfvars (optional)

To provide values for the variables, create a `terraform.tfvars` file:

```hcl
ssh_public_key = "ssh-rsa AAAA..." # Your SSH public key
ssh_allowed_ips = ["203.0.113.1/32"] # Your IP address
meilisearch_allowed_ips = ["203.0.113.1/32"] # Your IP address
http_allowed_ips = ["203.0.113.1/32"] # Your IP address
https_allowed_ips = ["203.0.113.1/32"] # Your IP address
```

## Deploying the infrastructure

Now that your configuration is complete, you can deploy Meilisearch:

1. Verify your configuration:

```bash
terraform validate
```

2. Preview the changes Terraform will make:

```bash
terraform plan
```

3. Apply the configuration to create the infrastructure:

```bash
terraform apply
```

When prompted, type `yes` to confirm. Terraform will:
- Create the VPC, subnet, internet gateway, and route table
- Configure the security group with IP restrictions
- Launch an EC2 t4g.micro instance with the latest Ubuntu ARM AMI
- Run the user data script to install and configure Meilisearch

4. After completion, Terraform will output:
- The public IP of your Meilisearch instance
- The public DNS name
- The Meilisearch endpoint URL
- The master key (sensitive, view with `terraform output meilisearch_master_key`)

## Accessing and verifying Meilisearch

Once your instance is running and the user data script completes (which may take a few minutes), you can verify Meilisearch is working:

1. Check if Meilisearch is responding:

```bash
curl http://<instance-ip>:7700/health
```

You should see a response like `{"status":"available"}`.

2. Test with authentication (using your master key):

```bash
curl \
  -X GET 'http://<instance-ip>:7700/indexes' \
  -H 'Authorization: Bearer <master-key>'
```

This should return an empty array of indexes `[]`.

3. Create a test index:

```bash
curl \
  -X POST 'http://<instance-ip>:7700/indexes' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <master-key>' \
  --data-binary '{"uid": "test-index"}'
```

## Best practices for production deployment

For a production-ready Meilisearch deployment on t4g.micro, consider these **essential optimizations**:

### Security enhancements

1. **Restrict IP access**: Update your `terraform.tfvars` file to limit access to specific IP addresses for all ingress rules.

2. **API key management**: Create specific API keys instead of using the master key:

```bash
# Create a search-only key
curl \
  -X POST 'http://<instance-ip>:7700/keys' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <master-key>' \
  --data-binary '{
    "description": "Search only key",
    "actions": ["search"],
    "indexes": ["*"],
    "expiresAt": null
  }'
```

3. **Enable HTTPS**: Install a valid SSL certificate using Let's Encrypt:

```bash
# Add to user data script to automatically configure
apt-get install -y certbot python3-certbot-nginx
certbot --nginx -d yourdomain.com --non-interactive --agree-tos -m your@email.com
```

### Performance optimization for t4g.micro

The t4g.micro has 2 vCPUs and 1GB RAM, which requires careful configuration for Meilisearch:

1. **Memory management** is critical - the configuration limits indexing memory to 1 GiB with:

```
max_indexing_memory = "1 GiB"
```

2. **Index optimization**: Limit the number of searchable attributes to reduce memory usage:

```bash
curl \
  -X PUT 'http://<instance-ip>:7700/indexes/your-index/settings/searchable-attributes' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <master-key>' \
  --data-binary '["title", "description"]'
```

3. **Document limitation**: A t4g.micro can typically handle up to 100k documents efficiently, depending on their size and complexity.

4. **CPU credits**: The configuration enables unlimited CPU credits, which helps with burst operations but may increase cost slightly.

## Monitoring and maintenance for ARM deployments

### Monitoring setup

1. **CloudWatch Alarms**: Add these resources to your Terraform configuration:

```hcl
resource "aws_cloudwatch_metric_alarm" "meilisearch_cpu" {
  alarm_name          = "meilisearch-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors EC2 cpu utilization"
  dimensions = {
    InstanceId = aws_instance.meilisearch.id
  }
}
```

2. **Meilisearch metrics**: Enable the metrics endpoint for Prometheus integration:

```bash
curl \
  -X PATCH 'http://<instance-ip>:7700/experimental-features/' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <master-key>' \
  --data-binary '{ "metrics": true }'
```

Access metrics at `http://<instance-ip>:7700/metrics`.

### ARM-specific maintenance

1. **Memory monitoring** is particularly important with ARM instances:

```bash
# Add to user data script
apt-get install -y amazon-cloudwatch-agent
```

Configure the CloudWatch agent to monitor memory usage, which is critical for t4g.micro instances:

```json
{
  "metrics": {
    "append_dimensions": {
      "InstanceId": "${aws_ec2_metadata_instance_id}"
    },
    "metrics_collected": {
      "mem": {
        "measurement": [
          "mem_used_percent"
        ]
      }
    }
  }
}
```

2. **Backup strategy**:

Meilisearch automates snapshots with the configuration:

```
schedule_snapshot = 86400  # Create snapshots every 24 hours
```

You can also create EBS snapshots using AWS Backup:

```hcl
resource "aws_backup_plan" "meilisearch" {
  name = "meilisearch-backup-plan"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.meilisearch.name
    schedule          = "cron(0 3 * * ? *)"  # 3 AM UTC daily
    start_window      = 60
    completion_window = 120
  }
}
```

3. **ARM architecture optimization**:

The t4g.micro performs well for small to medium workloads, but consider these ARM-specific tips:

- **Performance monitoring**: ARM processors handle smaller, parallel tasks more efficiently than single-threaded performance
- **Upgrade path**: If you need more capacity, t4g.small (2GB RAM) or t4g.medium (4GB RAM) provide good scaling options
- **Storage optimization**: Use gp3 volumes (as configured) for better performance-to-cost ratio on ARM instances

## Conclusion

You now have a secure, cost-effective Meilisearch deployment running on AWS Graviton2 ARM architecture. The t4g.micro provides an excellent balance of performance and cost for small to medium-sized search applications, with appropriate memory limits configured for this instance type.

For larger indexes or higher traffic, consider upgrading to larger t4g instance types while keeping the same configuration structure. The ARM-based instances provide better price-performance than equivalent x86 instances, making them ideal for search workloads.