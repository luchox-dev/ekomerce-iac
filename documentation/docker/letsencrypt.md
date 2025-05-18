# Let's Encrypt Docker Service

This Docker image provides a tool for automating wildcard certificate generation and management using Let's Encrypt with DNS validation via Cloudflare.

## Overview

The Let's Encrypt Docker service is designed to:

1. Generate wildcard SSL certificates for domains managed through Cloudflare
2. Automate certificate renewal processes
3. Provide a lightweight Ubuntu-based environment for running the certificate management script

## Docker Image Details

- **Base Image**: Ubuntu 24.04
- **Installed Packages**: sudo, python3, curl
- **Primary Script**: letsencrypt_wildcard_setup.py

## Building the Image

```bash
# From the repository root
docker build -t letsencrypt-service -f docker/Dockerfile.letsencrypt .
```

## Configuration

Before using the image, you'll need to configure the following parameters in the `letsencrypt_wildcard_setup.py` script:

- `DOMAIN`: Your domain for certificate generation (e.g., '*.example.com')
- `EMAIL`: Your email address for Let's Encrypt notifications
- `DNS_API_KEY`: Your Cloudflare API key

## Usage

### Basic Usage

```bash
# Run the container
docker run --rm -it letsencrypt-service

# Inside the container, run the script
python3 /usr/local/bin/letsencrypt_wildcard_setup.py
```

### Using with Environment Variables

```bash
docker run --rm -it \
  -e DOMAIN="*.example.com" \
  -e EMAIL="your@email.com" \
  -e DNS_API_KEY="your-cloudflare-api-key" \
  letsencrypt-service python3 /usr/local/bin/letsencrypt_wildcard_setup.py
```

### Persisting Certificates

To save the generated certificates, mount a volume:

```bash
docker run --rm -it \
  -v /path/to/local/certs:/etc/letsencrypt \
  letsencrypt-service
```

## Integration with Other Services

This Docker service is often used in conjunction with:

- Nginx for serving web content with SSL
- Web applications that require secure connections
- DevOps automation workflows

## Security Considerations

- Cloudflare API keys are sensitive and should be handled securely
- Consider using environment variables or secure vaults for API keys
- The script stores your Cloudflare API key in `/etc/letsencrypt/cloudflare/credentials.ini`
- File permissions are set to 600 (readable only by root)

## See Also

- [Let's Encrypt Automation Guide](../README-letsencrypt-automation.md)
- [Docker Test Environment](./README-letsencrypt-test.md)