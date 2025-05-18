#!/usr/bin/env python3
"""
Let's Encrypt Wildcard Certificate Automation Script with Nginx Reverse Proxy Configuration

This script automates the process of obtaining and renewing wildcard certificates using 
Let's Encrypt with Cloudflare DNS validation on Ubuntu 24.04. It also configures Nginx
as a secure reverse proxy for the API.

Author: Claude
Updated: 2025
"""

import os
import sys
import subprocess
import logging
import time
import json
from datetime import datetime
from pathlib import Path

# Configuration Variables
DOMAIN = '*.qleber.co'  # Wildcard domain
EMAIL = 'luis@qleber.co'  # Contact email for Let's Encrypt
DNS_API_KEY = 'aK7fDaYfuVifBm1aiZ0F_JYR2n7VoE9iX-7GUIZz'  # Cloudflare API Key
BASE_DOMAIN = DOMAIN.replace('*.', '')  # Extract base domain (qleber.co)
API_SUBDOMAIN = f"api.{BASE_DOMAIN}"  # API subdomain
API_UPSTREAM_PORT = 8080  # Local port where API is running

# Setup logging
LOG_DIR = "/var/log/letsencrypt-automation"
LOG_FILE = f"{LOG_DIR}/letsencrypt-automation-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"

def setup_logging():
    """Configure logging to both file and console."""
    os.makedirs(LOG_DIR, exist_ok=True)
    
    # Configure logging format
    log_format = '%(asctime)s - %(levelname)s - %(message)s'
    logging.basicConfig(
        level=logging.INFO,
        format=log_format,
        handlers=[
            logging.FileHandler(LOG_FILE),
            logging.StreamHandler(sys.stdout)
        ]
    )
    logging.info(f"Script started. Logs will be saved to {LOG_FILE}")

def run_command(command, description=None, shell=False):
    """
    Execute a shell command and log the output.
    
    Args:
        command: Command to execute (list or string)
        description: Description of the command for logging
        shell: Whether to run the command in a shell
        
    Returns:
        tuple: (success boolean, output string)
    """
    if description:
        logging.info(f"TASK: {description}")
    
    cmd_str = command if isinstance(command, str) else " ".join(command)
    logging.info(f"Executing: {cmd_str}")
    
    try:
        if shell and isinstance(command, list):
            command = " ".join(command)
        
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            shell=shell,
            text=True
        )
        stdout, stderr = process.communicate()
        
        # Log stdout and stderr
        if stdout:
            for line in stdout.splitlines():
                logging.info(f"STDOUT: {line}")
        
        if stderr:
            for line in stderr.splitlines():
                logging.warning(f"STDERR: {line}")
        
        if process.returncode != 0:
            logging.error(f"Command failed with return code {process.returncode}")
            return False, stderr
        
        return True, stdout
    except Exception as e:
        logging.error(f"Exception during command execution: {str(e)}")
        return False, str(e)

def update_system():
    """Update system packages and install dependencies."""
    logging.info("PHASE: System Update and Dependencies Installation")
    
    steps = [
        ("Updating package lists", ["apt-get", "update", "-y"]),
        ("Upgrading packages", ["apt-get", "upgrade", "-y"]),
        ("Installing dependencies", [
            "apt-get", "install", "-y", 
            "nginx", "python3", "python3-pip", "certbot", "python3-certbot-dns-cloudflare"
        ])
    ]
    
    for description, command in steps:
        success, output = run_command(command, description)
        if not success:
            logging.error(f"Failed to {description.lower()}")
            return False
    
    return True

def configure_cloudflare_credentials():
    """Configure Cloudflare API credentials for Certbot."""
    logging.info("PHASE: Configuring Cloudflare credentials")
    
    credentials_dir = "/etc/letsencrypt/cloudflare"
    credentials_file = f"{credentials_dir}/credentials.ini"
    
    # Create directory
    os.makedirs(credentials_dir, exist_ok=True)
    
    # Create credentials file
    try:
        with open(credentials_file, 'w') as f:
            f.write(f"dns_cloudflare_api_token = {DNS_API_KEY}\n")
        
        # Secure the credentials file
        os.chmod(credentials_file, 0o600)
        logging.info(f"Created Cloudflare credentials file at {credentials_file}")
        return True
    except Exception as e:
        logging.error(f"Failed to create Cloudflare credentials file: {str(e)}")
        return False

def generate_certificate():
    """Generate wildcard certificate using Certbot and Cloudflare DNS."""
    logging.info(f"PHASE: Generating wildcard certificate for {DOMAIN}")
    
    # Check if we should skip actual certificate generation (for testing environments)
    if os.environ.get('SKIP_CERT_GENERATION') == 'true':
        logging.info("TESTING MODE: Skipping actual certificate generation")
        # Just check if certificate files exist from our mock environment
        cert_path = f"/etc/letsencrypt/live/{BASE_DOMAIN}/fullchain.pem"
        key_path = f"/etc/letsencrypt/live/{BASE_DOMAIN}/privkey.pem"
        
        if os.path.exists(cert_path) and os.path.exists(key_path):
            logging.info(f"Using existing certificate files at {cert_path}")
            return True
        else:
            logging.error("Certificate files not found in testing environment")
            return False
    
    # Normal production certificate generation
    command = [
        "certbot", "certonly", "--dns-cloudflare", 
        f"--dns-cloudflare-credentials=/etc/letsencrypt/cloudflare/credentials.ini",
        "--preferred-challenges=dns-01",
        f"--email={EMAIL}",
        "--agree-tos", "--no-eff-email",
        "-n",  # non-interactive
        "-d", f"{BASE_DOMAIN}",  # Base domain
        "-d", f"*.{BASE_DOMAIN}"  # Wildcard domain
    ]
    
    success, output = run_command(command, "Generating wildcard certificate")
    if not success:
        logging.error("Failed to generate certificate")
        return False
    
    # Verify certificate
    cert_path = f"/etc/letsencrypt/live/{BASE_DOMAIN}/fullchain.pem"
    key_path = f"/etc/letsencrypt/live/{BASE_DOMAIN}/privkey.pem"
    
    if os.path.exists(cert_path) and os.path.exists(key_path):
        logging.info(f"Certificate successfully generated at {cert_path}")
        return True
    else:
        logging.error("Certificate files not found. Certificate generation may have failed.")
        return False

def configure_renewal_hook():
    """Set up a renewal hook to reload Nginx after certificate renewal."""
    logging.info("PHASE: Configuring certificate renewal hook")
    
    renewal_hook_dir = "/etc/letsencrypt/renewal-hooks/deploy"
    os.makedirs(renewal_hook_dir, exist_ok=True)
    
    hook_script = f"{renewal_hook_dir}/nginx-reload.sh"
    
    try:
        with open(hook_script, 'w') as f:
            f.write(f"""#!/bin/bash
# Renewal hook for Let's Encrypt certificates
# This script is automatically executed when certificates are renewed

# Log the renewal
echo "[$(date)] Certificate renewal completed for {BASE_DOMAIN}" >> /var/log/letsencrypt-renewal.log

# Validate Nginx configuration before reloading
echo "Validating Nginx configuration..."
if ! /usr/sbin/nginx -t 2>/dev/null; then
    echo "[$(date)] ERROR: Nginx configuration is invalid. Manual intervention required." >> /var/log/letsencrypt-renewal.log
    exit 1
fi

# Reload Nginx to apply the renewed certificates
echo "Reloading Nginx after certificate renewal"
systemctl reload nginx

# Verify Nginx is running after reload
if ! systemctl is-active --quiet nginx; then
    echo "[$(date)] ERROR: Nginx failed to reload properly after certificate renewal" >> /var/log/letsencrypt-renewal.log
    
    # Attempt to restart Nginx if reload failed
    echo "Attempting to restart Nginx..."
    systemctl restart nginx
    
    if ! systemctl is-active --quiet nginx; then
        echo "[$(date)] CRITICAL: Nginx failed to restart after certificate renewal" >> /var/log/letsencrypt-renewal.log
    else
        echo "[$(date)] Nginx restarted successfully after failed reload" >> /var/log/letsencrypt-renewal.log
    fi
else
    echo "[$(date)] Nginx reloaded successfully after certificate renewal" >> /var/log/letsencrypt-renewal.log
fi
""")
        
        # Make the script executable
        os.chmod(hook_script, 0o755)
        logging.info(f"Created renewal hook at {hook_script}")
        
        # Create a log file for certificate renewals
        with open("/var/log/letsencrypt-renewal.log", 'a') as f:
            f.write(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Renewal hook script installed for {BASE_DOMAIN}\n")
        
        # Set proper permissions for the log file
        os.chmod("/var/log/letsencrypt-renewal.log", 0o644)
        
        return True
    except Exception as e:
        logging.error(f"Failed to create renewal hook: {str(e)}")
        return False

def configure_nginx():
    """Configure Nginx to use the new certificate and set up as a reverse proxy for the API."""
    logging.info("PHASE: Configuring Nginx with the new certificate and as a reverse proxy")
    
    # Create Nginx configuration directory if it doesn't exist
    nginx_conf_dir = "/etc/nginx/sites-available"
    nginx_enabled_dir = "/etc/nginx/sites-enabled"
    
    os.makedirs(nginx_conf_dir, exist_ok=True)
    os.makedirs(nginx_enabled_dir, exist_ok=True)
    os.makedirs("/etc/nginx/conf.d", exist_ok=True)
    
    # Create Nginx main configuration with security settings
    main_ssl_conf = "/etc/nginx/conf.d/ssl-params.conf"
    ssl_params = """# SSL parameters that can be shared between sites
# Improved SSL settings for security that won't conflict with defaults
# SSL protocols and ciphers (not duplicating the directives in the server blocks)
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
# Security headers
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
"""
    try:
        with open(main_ssl_conf, 'w') as f:
            f.write(ssl_params)
        logging.info(f"Created SSL parameters configuration at {main_ssl_conf}")
    except Exception as e:
        logging.error(f"Failed to create SSL parameters file: {str(e)}")
        return False
    
    # Create API reverse proxy configuration
    api_config_content = f"""# Upstream block for API backend
upstream api_backend {{
    server 127.0.0.1:{API_UPSTREAM_PORT};
    keepalive 32;
}}

# HTTP Server Block - Redirect to HTTPS
server {{
    listen 80;
    server_name {API_SUBDOMAIN};
    
    # Logging configuration
    access_log /var/log/nginx/{API_SUBDOMAIN}_access.log;
    error_log /var/log/nginx/{API_SUBDOMAIN}_error.log;
    
    # Redirect all HTTP requests to HTTPS
    location / {{
        return 301 https://$host$request_uri;
    }}
}}

# HTTPS Server Block - Proxy to API
server {{
    listen 443 ssl http2;
    server_name {API_SUBDOMAIN};
    
    # Logging configuration
    access_log /var/log/nginx/{API_SUBDOMAIN}_access.log;
    error_log /var/log/nginx/{API_SUBDOMAIN}_error.log;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/{BASE_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{BASE_DOMAIN}/privkey.pem;
    
    # Include common SSL parameters
    include /etc/nginx/conf.d/ssl-params.conf;
    
    # HSTS (15768000 seconds = 6 months)
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains" always;
    
    # Proxy settings
    location / {{
        proxy_pass http://api_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_buffering off;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
        
        # Error handling
        proxy_intercept_errors on;
        error_page 500 502 503 504 /50x.html;
    }}
    
    # Custom error pages
    location = /50x.html {{
        root /var/www/html;
    }}
}}
"""
    
    # Create a default server block for other subdomains
    default_config_content = f"""# HTTP Server Block - Redirect to HTTPS
server {{
    listen 80 default_server;
    server_name {BASE_DOMAIN} *.{BASE_DOMAIN};
    
    # Logging configuration
    access_log /var/log/nginx/default_access.log;
    error_log /var/log/nginx/default_error.log;
    
    # Redirect all HTTP requests to HTTPS
    location / {{
        return 301 https://$host$request_uri;
    }}
}}

# HTTPS Default Server Block
server {{
    listen 443 ssl http2 default_server;
    server_name {BASE_DOMAIN} *.{BASE_DOMAIN};
    
    # Logging configuration
    access_log /var/log/nginx/default_ssl_access.log;
    error_log /var/log/nginx/default_ssl_error.log;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/{BASE_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{BASE_DOMAIN}/privkey.pem;
    
    # Include common SSL parameters
    include /etc/nginx/conf.d/ssl-params.conf;
    
    # HSTS (15768000 seconds = 6 months)
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains" always;
    
    # Default location block
    location / {{
        root /var/www/html;
        index index.html;
    }}
}}
"""
    
    # Write the configuration files
    try:
        # Create API config
        api_conf_path = f"/etc/nginx/sites-available/{API_SUBDOMAIN}"
        with open(api_conf_path, 'w') as f:
            f.write(api_config_content)
        logging.info(f"Created API reverse proxy configuration at {api_conf_path}")
        
        # Create default config
        default_conf_path = f"/etc/nginx/sites-available/default"
        with open(default_conf_path, 'w') as f:
            f.write(default_config_content)
        logging.info(f"Created default server configuration at {default_conf_path}")
        
        # Create symlinks to enable the sites
        api_enabled_path = f"/etc/nginx/sites-enabled/{API_SUBDOMAIN}"
        default_enabled_path = f"/etc/nginx/sites-enabled/default"
        
        # Remove existing symlinks if they exist
        if os.path.exists(api_enabled_path):
            os.remove(api_enabled_path)
        if os.path.exists(default_enabled_path):
            os.remove(default_enabled_path)
        
        # Create new symlinks
        os.symlink(api_conf_path, api_enabled_path)
        os.symlink(default_conf_path, default_enabled_path)
        logging.info("Enabled Nginx site configurations")
        
        # Create a test page and custom error pages
        os.makedirs("/var/www/html", exist_ok=True)
        
        # Create test index.html
        with open("/var/www/html/index.html", 'w') as f:
            f.write(f"""<!DOCTYPE html>
<html>
<head>
    <title>SSL Test for {BASE_DOMAIN}</title>
</head>
<body>
    <h1>SSL Certificate Test</h1>
    <p>This site is secured with a Let's Encrypt wildcard certificate.</p>
    <p>Domain: {BASE_DOMAIN}</p>
    <p>Generated on: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
</body>
</html>
""")
        
        # Create custom error page
        with open("/var/www/html/50x.html", 'w') as f:
            f.write(f"""<!DOCTYPE html>
<html>
<head>
    <title>Server Error - {BASE_DOMAIN}</title>
    <style>
        body {{ font-family: Arial, sans-serif; color: #333; text-align: center; padding: 50px; }}
        .error-container {{ max-width: 600px; margin: 0 auto; }}
        h1 {{ color: #e74c3c; }}
    </style>
</head>
<body>
    <div class="error-container">
        <h1>Server Error</h1>
        <p>Sorry, the server encountered an error and was unable to complete your request.</p>
        <p>Our team has been notified and we're working to fix the issue.</p>
        <p>Please try again later.</p>
    </div>
</body>
</html>
""")
        
        # Test the Nginx configuration
        success, output = run_command(["nginx", "-t"], "Testing Nginx configuration")
        if not success:
            logging.error("Nginx configuration test failed")
            return False
        
        # Reload Nginx
        success, output = run_command(["systemctl", "reload", "nginx"], "Reloading Nginx")
        if not success:
            logging.error("Failed to reload Nginx")
            return False
        
        logging.info(f"Nginx configured successfully as a reverse proxy for {API_SUBDOMAIN}")
        return True
    except Exception as e:
        logging.error(f"Failed to configure Nginx: {str(e)}")
        return False

def test_certificate():
    """Test the certificate and Nginx configuration."""
    logging.info(f"PHASE: Testing SSL certificate and Nginx configuration for {BASE_DOMAIN} and {API_SUBDOMAIN}")
    
    # Check if the certificate files exist
    cert_path = f"/etc/letsencrypt/live/{BASE_DOMAIN}/fullchain.pem"
    key_path = f"/etc/letsencrypt/live/{BASE_DOMAIN}/privkey.pem"
    
    if not os.path.exists(cert_path) or not os.path.exists(key_path):
        logging.error("Certificate files not found.")
        return False
    
    logging.info("Certificate files exist.")
    
    # Test Nginx configuration syntax
    success, output = run_command(["nginx", "-t"], "Testing Nginx configuration syntax")
    if not success:
        logging.error("Nginx configuration syntax is invalid.")
        return False
    
    logging.info("Nginx configuration syntax is valid.")
    
    # Test if Nginx is running
    success, output = run_command(["systemctl", "status", "nginx"], "Checking Nginx service status")
    if not success:
        logging.error("Nginx service is not running properly.")
        return False
    
    logging.info("Nginx service is running.")
    
    logging.info(f"Configuration testing completed for {BASE_DOMAIN} and {API_SUBDOMAIN}")
    logging.info(f"To fully test externally, please visit https://{API_SUBDOMAIN} in a browser")
    
    return True

def main():
    """Main function to orchestrate the certificate setup process."""
    setup_logging()
    
    logging.info("=" * 80)
    logging.info(f"Starting Let's Encrypt wildcard certificate automation for {DOMAIN}")
    logging.info(f"Configuring Nginx reverse proxy for {API_SUBDOMAIN}")
    logging.info("=" * 80)
    
    # Verify running as root
    if os.geteuid() != 0:
        logging.error("This script must be run as root. Please use sudo.")
        return False
    
    # Track overall success
    success = True
    
    # Define the phases of the process
    phases = [
        ("Updating system and installing dependencies", update_system),
        ("Configuring Cloudflare credentials", configure_cloudflare_credentials),
        ("Generating wildcard certificate", generate_certificate),
        ("Configuring renewal hook", configure_renewal_hook),
        ("Configuring Nginx as reverse proxy", configure_nginx),
        ("Testing SSL certificate and Nginx configuration", test_certificate)
    ]
    
    # Execute each phase
    for description, function in phases:
        logging.info("\n" + "=" * 50)
        logging.info(f"STARTING: {description}")
        logging.info("=" * 50)
        
        phase_success = function()
        if not phase_success:
            logging.error(f"FAILED: {description}")
            success = False
            break
        
        logging.info(f"COMPLETED: {description}")
    
    # Print summary
    logging.info("\n" + "=" * 80)
    if success:
        logging.info("SUCCESS: Let's Encrypt wildcard certificate setup completed successfully!")
        logging.info(f"Certificate is now available for {DOMAIN}")
        logging.info(f"Nginx has been configured as a reverse proxy for {API_SUBDOMAIN}")
        logging.info(f"API requests will be forwarded to port {API_UPSTREAM_PORT}")
        logging.info(f"Automatic renewal is set up with Certbot")
        logging.info("\nNext Steps:")
        logging.info(f"1. Ensure your API is running on port {API_UPSTREAM_PORT}")
        logging.info(f"2. Test your API through the secure proxy at https://{API_SUBDOMAIN}")
    else:
        logging.error("FAILED: Let's Encrypt wildcard certificate setup failed")
        logging.error("Please check the logs for details on what went wrong")
    
    logging.info("=" * 80)
    logging.info(f"Log file is available at: {LOG_FILE}")
    logging.info(f"Renewal logs will be written to: /var/log/letsencrypt-renewal.log")
    
    return success

if __name__ == "__main__":
    result = main()
    sys.exit(0 if result else 1)