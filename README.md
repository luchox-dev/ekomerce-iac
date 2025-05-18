# E-Komerce Infrastructure as Code (IaC)

This repository contains the infrastructure as code (IaC) resources for deploying and managing the E-Komerce platform. It provides a collection of Terraform configurations, scripts, and documentation for automating the deployment and operation of e-commerce infrastructure.

## Overview

The E-Komerce IaC repository is designed to:

1. **Provision Cloud Infrastructure** - Using Terraform to create and manage AWS resources
2. **Deploy Microservices** - Configure and manage application services
3. **Automate Security** - Manage SSL certificates and secure application access
4. **Enable Search Functionality** - Deploy and configure Meilisearch for fast, relevant product searches
5. **Support Multiple Environments** - Enable dev, staging, and production deployments

## Repository Structure

The repository follows a layered architecture approach to improve maintainability and simplify the deployment workflow:

```
ekomerce-iac/
├── layers/                # Layered Terraform architecture
│   ├── 01-core/           # Core infrastructure (VPC, security groups, EIPs)
│   ├── 02-compute/        # Compute resources (EC2 instances, AMIs)
│   ├── 03-database/       # Database resources (Redis, MeiliSearch)
│   ├── 04-application/    # Application deployment (provisioners, scripts)
│   └── 05-environment/    # Environment configuration (dev, staging, prod)
├── documentation/         # Project documentation
├── docker/                # Docker service definitions
├── scripts/               # Automation scripts
│   ├── create-s3-backend.sh
│   ├── github_repo_clone.py
│   ├── init-layers.sh     # Initialize all layers' state
│   ├── validate-layers.sh # Validate all layers
│   ├── apply-layers.sh    # Apply all layers in sequence
│   └── ...
├── conn_keys/             # Connection keys (gitignored)
└── ssh_keys/              # SSH keys for deployments (gitignored)
```

## Layered Architecture

### 1. Core Layer

The core layer contains foundational infrastructure resources:
- VPC and networking configuration
- Common security groups
- Elastic IPs for service endpoints
- Core IAM roles and policies

### 2. Compute Layer

Manages all compute-related components:
- EC2 instances definitions
- AMI selection and configuration
- Auto-scaling groups (when applicable)
- Instance security groups

### 3. Database Layer

Handles all database and cache services:
- Redis configuration
- MeiliSearch setup
- DynamoDB tables (when applicable)

This layer is designed to be modular, allowing each database service to be recreated independently.

### 4. Application Layer

Deploys application-specific services:
- Backend application provisioning
- Configuration management
- Service connectivity
- Repository deployment

### 5. Environment Layer

Manages environment-specific configurations:
- Environment variables for each environment (dev, staging, production)
- Environment-specific resources and settings
- Workspace-based isolation between environments

## Getting Started

### Prerequisites

- AWS CLI installed and configured
- Terraform 1.0+ installed
- Docker and Docker Compose installed (optional, for local testing)
- SSH keys for secure connections

### Initial Setup

1. Clone this repository:
   ```bash
   git clone git@github.com:your-org/ekomerce-iac.git
   cd ekomerce-iac
   ```

2. Create connection keys directory and add your EC2 access key:
   ```bash
   mkdir -p conn_keys
   cp /path/to/your/ec2-access.pem conn_keys/
   chmod 600 conn_keys/ec2-access.pem
   ```

3. Initialize all layers:
   ```bash
   ./scripts/init-layers.sh
   ```

### Deploying Infrastructure

1. Apply each layer in sequence:
   ```bash
   ./scripts/apply-layers.sh dev  # Replace 'dev' with desired environment
   ```

   This will:
   - Create all core infrastructure
   - Set up compute resources
   - Configure database services
   - Deploy application components
   - Apply environment-specific settings

2. Alternatively, deploy specific layers:
   ```bash
   cd layers/01-core
   terraform apply -var="environment=dev"
   ```

## Managing Multiple Environments

The infrastructure supports multiple environments using Terraform workspaces:

```bash
# Create a new environment
cd layers/01-core
terraform workspace new staging
terraform apply -var="environment=staging"

# Or use the script for all layers
./scripts/apply-layers.sh staging
```

## Documentation

For detailed information about specific components, refer to the documentation directory:

- [Meilisearch Local Development](documentation/meilisearch-local.md)
- [Meilisearch AWS Deployment](documentation/meilisearch-aws-deployment.md)
- [Let's Encrypt Automation](documentation/letsencrypt-automation.md)
- [GitHub Clone Script](documentation/github-clone-script.md)
- [Docker Services](documentation/docker/index.md)

## Best Practices

1. **State Management**:
   - Each layer maintains its own state file
   - Use remote state with S3 backend and DynamoDB locking
   - Reference outputs from other layers using `terraform_remote_state`

2. **Security**:
   - Store sensitive values in Terraform variables, not directly in code
   - Use environment-specific security settings
   - Restrict access using security groups and IAM policies

3. **Modularity**:
   - Keep each layer focused on a specific aspect of infrastructure
   - Define clear interfaces between layers with outputs and remote state
   - Enable independent updates to specific layers

## Contributing

Contributions are welcome! Please read the [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.