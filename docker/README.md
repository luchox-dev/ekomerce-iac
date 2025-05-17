# E-Komerce Infrastructure Docker Services

This directory contains Docker services that support the E-Komerce infrastructure. These services work together to provide a robust deployment and operations environment for the e-commerce platform.

## Overview

The Docker services in this repository are organized to support several key infrastructure components:

1. **Let's Encrypt Certification** - Automated SSL certificate generation and renewal
2. **GitHub Repository Deployment** - Secure cloning of private repositories
3. **Meilisearch** - Fast, relevant search capabilities for e-commerce
4. **Testing Environments** - Controlled testing of infrastructure components

## Available Docker Services

| Service | Description | Documentation |
|---------|-------------|---------------|
| Let's Encrypt | Automates wildcard certificate generation via Cloudflare DNS validation | [README](./README-letsencrypt.md) |
| GitHub Clone | Securely clones private GitHub repositories using SSH | [README](./README-github-clone.md) |
| Meilisearch | Provides a fast, typo-tolerant search engine | [README](./README-meilisearch.md) |
| Let's Encrypt Test | Testing environment for certificate automation | [README](./README-letsencrypt-test.md) |

## Project Workflow

The Docker services in this project support the following workflow:

1. **Infrastructure Provisioning**
   - Terraform creates AWS resources (EC2, VPC, etc.)
   - Docker containers can be deployed directly on EC2 instances

2. **Repository Deployment**
   - The GitHub Clone service securely pulls application code
   - SSH keys and authentication are handled automatically

3. **SSL Certificate Management**
   - Let's Encrypt service obtains wildcard certificates
   - Certificates are renewed automatically
   - Nginx configuration is updated with new certificates

4. **Search Functionality**
   - Meilisearch provides fast, relevant product search
   - Can be deployed locally for development or on EC2 for production

## Building and Using the Services

### Common Docker Commands

```bash
# Build all images (from repository root)
docker build -t letsencrypt-service -f docker/Dockerfile.letsencrypt .
docker build -t github-clone-service -f docker/Dockerfile.github-clone .
docker build -t meilisearch-service -f docker/Dockerfile.meilisearch .

# Run the Let's Encrypt test environment
docker-compose -f docker/docker-compose.letsencrypt-test.yml up --build
```

### Local Development Environment

For local development, use the following pattern:

```bash
# Start Meilisearch for local development
docker run -d --name meilisearch \
  -p 7700:7700 \
  -e MEILISEARCH_MASTER_KEY=dev_key \
  -v meilisearch_data:/var/lib/meilisearch \
  meilisearch-service
```

### CI/CD Integration

The services can be integrated into CI/CD pipelines:

```bash
# Example: Test Let's Encrypt certificate automation
docker-compose -f docker/docker-compose.letsencrypt-test.yml up -d
docker exec docker-ubuntu-1 /usr/local/bin/run-test.sh
docker-compose -f docker/docker-compose.letsencrypt-test.yml down

# Example: Clone repository in CI environment
docker run --rm \
  -v /path/to/deployment/keys:/app/ssh_keys \
  github-clone-service \
  python3 /app/github_repo_clone.py \
  --ssh-dir /app/ssh_keys \
  --dest-dir /build/app \
  --repo git@github.com:username/repository.git
```

## Production Deployment

For production deployments, follow these best practices:

1. **Security**:
   - Change all default passwords and API keys
   - Use environment variables to inject secrets
   - Follow least privilege principles for containers

2. **Data Persistence**:
   - Use named volumes for all stateful services
   - Implement backup strategies for data volumes

3. **Monitoring**:
   - Configure log collection for all containers
   - Set up health checks for each service

## Common Operations

### Updating Dockerfiles

When updating Dockerfiles:

1. Make changes to the appropriate Dockerfile in the `docker/` directory
2. Update the corresponding README file if necessary
3. Rebuild the affected image with the updated Dockerfile

### Adding a New Service

To add a new Docker service:

1. Create a new Dockerfile in the `docker/` directory
2. Create a README.md file documenting the service
3. Update this main README.md to include the new service
4. If needed, create a docker-compose.yml file for the service

## Additional Resources

- [Main Project README](../README.md)
- [Let's Encrypt Automation Guide](../README-letsencrypt-automation.md)
- [GitHub Clone Script Guide](../README-github-clone-script.md)
- [Meilisearch AWS Deployment Guide](../deploy_meilisearch_on_aws_ec2.md)