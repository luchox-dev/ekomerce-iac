#!/bin/bash
# Meilisearch installation and configuration script for Ubuntu 24.04 on AWS EC2

# Enable error handling but allow undefined variables for template substitution
set -eo pipefail

# Log all script output to a file for troubleshooting
exec > >(tee /var/log/meilisearch-setup.log) 2>&1
echo "Starting Meilisearch installation script at $(date)"

# Wait for cloud-init to complete (with timeout to prevent hanging)
echo "Waiting for cloud-init to complete..."
timeout 180 cloud-init status --wait || echo "Warning: cloud-init wait timed out after 3 minutes, continuing anyway"

# Update system packages
echo "Updating system packages..."
apt-get update && apt-get upgrade -y

# Install required dependencies
echo "Installing required dependencies..."
apt-get install -y curl systemd ufw

# Create a user for Meilisearch
echo "Creating meilisearch user..."
useradd -d /var/lib/meilisearch -s /bin/false -m -r meilisearch

# Install Meilisearch using the official script
echo "Installing Meilisearch..."
curl -L https://install.meilisearch.com | sh

# Check if installation was successful
if [ ! -f ./meilisearch ]; then
  echo "ERROR: Meilisearch binary not found after installation!"
  exit 1
fi

# Move the binary to a standard location
echo "Moving Meilisearch binary to /usr/local/bin/..."
mv ./meilisearch /usr/local/bin/

# Verify binary is executable
echo "Verifying Meilisearch binary..."
chmod +x /usr/local/bin/meilisearch
if ! /usr/local/bin/meilisearch --version; then
  echo "ERROR: Meilisearch binary is not executable or not working!"
  echo "Checking binary details:"
  ls -la /usr/local/bin/meilisearch
  file /usr/local/bin/meilisearch
  ldd /usr/local/bin/meilisearch || echo "Not a dynamic executable"
  exit 1
fi

# Create directories for Meilisearch data
echo "Creating Meilisearch data directories..."
mkdir -p /var/lib/meilisearch/data /var/lib/meilisearch/dumps /var/lib/meilisearch/snapshots
chown -R meilisearch:meilisearch /var/lib/meilisearch
chmod 750 /var/lib/meilisearch

echo "Verifying directory permissions..."
ls -la /var/lib/meilisearch

# Create config file with template variables replaced
echo "Creating Meilisearch configuration file..."

# Verify we have a master key
if [ -z "${master_key}" ]; then
  echo "ERROR: master_key variable is undefined! This is required for secure operation."
  echo "Check that Terraform properly substituted the variable in the template."
  exit 1
fi

# Write configuration file with proper escaping of variables
cat > /etc/meilisearch.toml << EOF
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

# Verify config file was created properly (without printing the master key)
echo "Verifying config file creation..."
if [ -f /etc/meilisearch.toml ]; then
  echo "Config file created successfully."
  grep -v master_key /etc/meilisearch.toml
else
  echo "ERROR: Failed to create config file!"
  exit 1
fi

# Create systemd service file
echo "Creating systemd service file..."
cat > /etc/systemd/system/meilisearch.service << EOF
[Unit]
Description=Meilisearch
After=network.target

[Service]
Type=simple
WorkingDirectory=/var/lib/meilisearch
ExecStart=/usr/local/bin/meilisearch --config-file-path /etc/meilisearch.toml
User=meilisearch
Group=meilisearch
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo "Verifying service file creation..."
if [ ! -f /etc/systemd/system/meilisearch.service ]; then
  echo "ERROR: Failed to create service file!"
  exit 1
fi

# Configure firewall
echo "Configuring firewall..."

# Verify we have the allowed_ip variable
if [ -z "${allowed_ip}" ]; then
  echo "ERROR: allowed_ip variable is undefined! This is required for secure operation."
  echo "Check that Terraform properly substituted the variable in the template."
  exit 1
fi

# Install ufw if not present (some minimal images might not have it)
if ! command -v ufw &> /dev/null; then
  echo "Installing ufw package..."
  apt-get install -y ufw
fi

# Configure the firewall rules
ufw default deny incoming
ufw default allow outgoing
echo "Allowing SSH access..."
ufw allow OpenSSH
echo "Allowing Meilisearch access from ${allowed_ip} only..."
ufw allow from "${allowed_ip}" to any port 7700 proto tcp
echo "Enabling firewall..."
ufw --force enable
echo "Firewall status:"
ufw status

# Check directory permissions one more time before starting the service
echo "Doing final permission check on data directories..."
find /var/lib/meilisearch -type d -exec chmod 750 {} \;
find /var/lib/meilisearch -exec chown meilisearch:meilisearch {} \;

# Enable and start Meilisearch service
echo "Starting Meilisearch service..."
systemctl daemon-reload
systemctl enable meilisearch
systemctl start meilisearch

# Verify service is running
echo "Verifying Meilisearch service status..."
sleep 10  # Give service more time to start (10 seconds)

# Try up to 3 times to start the service if it fails
max_attempts=3
attempt=1

while [ $attempt -le $max_attempts ]; do
  if systemctl is-active --quiet meilisearch; then
    echo "SUCCESS: Meilisearch service is running on attempt $attempt!"
    systemctl status meilisearch --no-pager
    break
  else
    echo "WARNING: Meilisearch service not running on attempt $attempt of $max_attempts"
    
    if [ $attempt -lt $max_attempts ]; then
      echo "Trying to restart the service..."
      systemctl restart meilisearch
      sleep 10  # Wait for restart
      attempt=$((attempt+1))
    else
      echo "ERROR: Meilisearch service failed to start after $max_attempts attempts!"
      systemctl status meilisearch --no-pager
      echo "Checking logs:"
      journalctl -u meilisearch --no-pager | tail -n 30
      echo "Checking config:"
      cat /etc/meilisearch.toml | grep -v master_key
      echo "Testing if we can manually run meilisearch:"
      su - meilisearch -s /bin/bash -c "cd ~ && /usr/local/bin/meilisearch --config-file-path /etc/meilisearch.toml --env-file" || echo "Manual run failed"
      break
    fi
  fi
done

echo "Meilisearch installation completed at $(date)"
echo "Service is listening on port 7700 and restricted to access from ${allowed_ip}"