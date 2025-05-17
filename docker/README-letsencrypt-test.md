# Let's Encrypt Test Docker Service

This Docker service provides a testing environment for the Let's Encrypt wildcard certificate automation script, allowing safe verification of configuration and functionality without actual certificate issuance.

## Overview

The Let's Encrypt Test service enables:

1. Testing SSL certificate automation in a safe, controlled environment
2. Verifying script functionality with mock services
3. Testing Nginx configuration and certificate deployment
4. Simulating the complete certificate workflow without external dependencies

## Docker Image Details

- **Base Image**: Ubuntu 24.04
- **Exposed Ports**: 80, 443
- **Installed Components**:
  - Nginx web server
  - Python 3 with dependencies
  - Mock Certbot environment
  - Self-signed certificates for testing

## Docker Compose Setup

This service uses Docker Compose to create a complete testing environment:

- **API Mock Service**: Simulates backend services
- **Ubuntu Container**: Runs the Let's Encrypt script in test mode

## Building and Running the Test Environment

```bash
# From the repository root
docker-compose -f docker/docker-compose.letsencrypt-test.yml up --build
```

## Test Components

### Mock API Service

A simple echo server that helps test reverse proxy functionality:
- Runs on port 8080 internally
- Accessible via the Ubuntu container

### Ubuntu Test Environment

Contains:
- Let's Encrypt wildcard setup script
- Mock Certbot implementation
- Self-signed certificates for testing
- Nginx for testing certificate deployment
- Mock systemd service manager

## Using the Test Environment

Once the environment is running, you can:

1. Access the Ubuntu container shell:
   ```bash
   docker exec -it docker-ubuntu-1 bash
   ```

2. Run the test script:
   ```bash
   /usr/local/bin/run-test.sh
   ```

3. Test Nginx with the certificates:
   ```bash
   curl -k https://api.qleber.co
   ```

## Customizing the Test

### Modifying the Test Domain

To change the domain used in tests:

1. Edit the `/usr/local/bin/run-test.sh` script inside the container
2. Update the hosts file entry and certificate paths

### Testing Different Script Parameters

You can modify the script behavior by setting environment variables:

```bash
# Inside the container
SKIP_CERT_GENERATION=true DOMAIN="*.example.org" python3 /usr/local/bin/letsencrypt_wildcard_setup.py
```

## Understanding the Mock Components

The test environment includes several mocks:

- **systemctl**: A mock implementation that supports basic Nginx operations
- **Certbot**: Bypassed to avoid real certificate issuance
- **Self-signed certificates**: Pre-generated for testing without Let's Encrypt

## Troubleshooting

If you encounter issues:

- Check the nginx logs: `/var/log/nginx/error.log`
- Verify the mock systemctl is working: `systemctl is-active nginx`
- Ensure hosts file entries are correct: `cat /etc/hosts`
- Check nginx configuration: `nginx -t`

## Integration with CI/CD

This test environment can be integrated with CI/CD pipelines:

```yaml
# Example GitHub Actions step
- name: Test Let's Encrypt script
  run: |
    docker-compose -f docker/docker-compose.letsencrypt-test.yml up -d
    docker exec docker-ubuntu-1 /usr/local/bin/run-test.sh
    docker-compose -f docker/docker-compose.letsencrypt-test.yml down
```

## See Also

- [Let's Encrypt Automation Guide](../README-letsencrypt-automation.md)
- [Let's Encrypt Docker Service](./README-letsencrypt.md)