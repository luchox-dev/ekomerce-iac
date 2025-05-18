# Let's Encrypt Wildcard Certificate Automation

This script automates the process of obtaining and renewing wildcard certificates using Let's Encrypt with Cloudflare DNS validation on Ubuntu 24.04.

## Overview

The script performs the following tasks:
1. Updates system packages and installs dependencies (nginx, python3, certbot, python3-certbot-dns-cloudflare)
2. Configures Cloudflare credentials for DNS-01 validation
3. Generates a wildcard certificate for your domain
4. Sets up automatic renewal with a hook to reload Nginx
5. Configures Nginx to use the new certificate
6. Creates a test page to verify the certificate

## Prerequisites

- Ubuntu 24.04 server (AWS EC2 t4g.micro recommended)
- Domain managed through Cloudflare DNS
- Cloudflare API key with DNS editing permissions

## Configuration

Edit the script to set the following variables at the top:
- `DOMAIN`: Your wildcard domain (e.g., '*.example.com')
- `EMAIL`: Your email address for Let's Encrypt notifications
- `DNS_API_KEY`: Your Cloudflare API key

## Usage

### Option 1: Run directly on your server

1. Upload the script to your server
2. Make it executable:
   ```
   chmod +x letsencrypt_wildcard_setup.py
   ```
3. Run with sudo:
   ```
   sudo ./letsencrypt_wildcard_setup.py
   ```

### Option 2: Test in Docker locally

1. Build the Docker image:
   ```
   docker build -t letsencrypt-test .
   ```
2. Run the container:
   ```
   docker run --rm -it letsencrypt-test /bin/bash
   ```
3. Inside the container, run the script:
   ```
   sudo ./usr/local/bin/letsencrypt_wildcard_setup.py
   ```

## Logs

The script generates detailed logs in two locations:
- Console output while running
- Log file at `/var/log/letsencrypt-automation/letsencrypt-automation-YYYYMMDD-HHMMSS.log`

## Troubleshooting

If the script fails, check the logs for detailed error messages. Common issues include:
- Network connectivity problems
- Invalid Cloudflare API key
- DNS propagation delays (DNS-01 validation requires DNS changes to propagate)
- Permission issues with Nginx configuration

## Security Notes

- The script stores your Cloudflare API key in `/etc/letsencrypt/cloudflare/credentials.ini`
- The file permissions are set to 600 (readable only by root)
- For production, consider using a Cloudflare API token with limited permissions