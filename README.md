# E-Komerce Infrastructure as Code (IaC)

This repository contains the infrastructure as code (IaC) resources for deploying and managing the E-Komerce platform. It provides a collection of Terraform configurations, Docker services, scripts, and documentation for automating the deployment and operation of e-commerce infrastructure.

## Overview

The E-Komerce IaC repository is designed to:

1. **Provision Cloud Infrastructure** - Using Terraform to create and manage AWS resources
2. **Deploy Microservices** - Utilize Docker for containerized service deployment
3. **Automate Security** - Manage SSL certificates and secure application access
4. **Enable Search Functionality** - Deploy and configure Meilisearch for fast, relevant product searches
5. **Maintain CI/CD Integration** - Support continuous deployment of application code

## Repository Structure

```
ekomerce-iac/
├── documentation/         # All project documentation
│   ├── docker/            # Docker-specific documentation
│   ├── github-clone-script.md
│   ├── letsencrypt-automation.md
│   ├── meilisearch-aws-deployment.md
│   └── meilisearch-local.md
├── docker/                # Docker service definitions
│   ├── Dockerfile.github-clone
│   ├── Dockerfile.letsencrypt
│   ├── Dockerfile.letsencrypt-test
│   ├── Dockerfile.meilisearch
│   └── docker-compose.letsencrypt-test.yml
├── scripts/               # Automation scripts
│   ├── create-s3-backend.sh
│   ├── github_repo_clone.py
│   ├── install_node.sh
│   ├── install_redis_on_ubunut24.04.sh
│   ├── letsencrypt_wildcard_setup.py
│   ├── meilisearch_userdata.sh
│   └── test_ssh_changes.sh
├── main.tf                # Main Terraform configuration
├── meilisearch.tf         # Meilisearch-specific Terraform config
├── terraform.tfvars       # Terraform variable values
├── terraform_examples.tf  # Example Terraform configurations
└── variables.tf           # Terraform variable definitions
```

## Key Components

### 1. Terraform Configurations

The repository provides Terraform configurations for provisioning:

- AWS EC2 instances for application hosting
- VPC, subnets, and security groups for network isolation
- S3 backends for state management
- Search service infrastructure (Meilisearch)

### 2. Docker Services

The included Docker services support:

- **Let's Encrypt** - Wildcard SSL certificate generation and renewal
- **GitHub Repository Deployment** - Secure cloning of private repositories
- **Meilisearch** - Fast, relevant search capabilities for e-commerce
- **Testing Environments** - Controlled testing of infrastructure components

### 3. Automation Scripts

Scripts in this repository automate common operations:

- Terraform state backend creation
- GitHub repository cloning with SSH authentication
- SSL certificate automation with Cloudflare DNS validation
- Node.js and Redis installation for application environments
- Meilisearch deployment and configuration

## Getting Started

### Prerequisites

- AWS CLI installed and configured
- Terraform 1.0+ installed
- Docker and Docker Compose installed
- Basic understanding of IaC concepts

### Initial Setup

1. Clone this repository:
   ```bash
   git clone https://github.com/your-org/ekomerce-iac.git
   cd ekomerce-iac
   ```

2. Create an S3 backend for Terraform state:
   ```bash
   ./scripts/create-s3-backend.sh your-terraform-state-bucket
   ```

3. Initialize Terraform:
   ```bash
   terraform init
   ```

4. Customize `terraform.tfvars` with your specific configuration values.

### Deploying Infrastructure

1. Review the planned changes:
   ```bash
   terraform plan
   ```

2. Apply the Terraform configuration:
   ```bash
   terraform apply
   ```

3. After deployment, Terraform will output important information like IP addresses and endpoints.

## Documentation

For detailed information about specific components, refer to the documentation directory:

- [Meilisearch Local Development](documentation/meilisearch-local.md)
- [Meilisearch AWS Deployment](documentation/meilisearch-aws-deployment.md)
- [Let's Encrypt Automation](documentation/letsencrypt-automation.md)
- [GitHub Clone Script](documentation/github-clone-script.md)
- [Docker Services](documentation/docker/index.md)

## Common Operations

### Adding a New Infrastructure Component

1. Create a new `.tf` file in the root directory
2. Define the resources and variables needed
3. Add documentation in the documentation directory
4. Update this README if necessary

### Building Docker Images

```bash
# Build all Docker images
docker build -t github-clone-service -f docker/Dockerfile.github-clone .
docker build -t letsencrypt-service -f docker/Dockerfile.letsencrypt .
docker build -t meilisearch-service -f docker/Dockerfile.meilisearch .
```

### Running Tests

```bash
# Test Let's Encrypt certificate automation
docker-compose -f docker/docker-compose.letsencrypt-test.yml up -d
docker exec docker-ubuntu-1 /usr/local/bin/run-test.sh
docker-compose -f docker/docker-compose.letsencrypt-test.yml down
```

## Best Practices for Production

1. **Security**:
   - Change all default passwords and API keys
   - Use environment variables for secrets
   - Restrict access to specific IP addresses

2. **State Management**:
   - Use remote state with encryption
   - Implement state locking
   - Consider using Terraform Cloud for team environments

3. **Monitoring**:
   - Set up monitoring for all deployed services
   - Configure alerting for critical failures
   - Implement logging solutions

## License

This project is licensed under the [Your License Type] - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please read the [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.