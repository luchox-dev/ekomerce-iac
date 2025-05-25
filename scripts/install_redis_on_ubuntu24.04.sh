#!/bin/bash
# Redis Server Setup Script – Ubuntu 24.04
# Parameters (to be replaced by Terraform template or passed via environment):
#   PRIVATE_IP       - Private IP address to bind Redis to (e.g., 10.0.1.5)
#   REDIS_USERNAME   - Username for Redis ACL authentication (e.g., "admin")
#   REDIS_PASSWORD   - Password for the above Redis user
#   ALLOWED_IP       - The single IP address allowed to connect to Redis (e.g., application server IP)

set -euo pipefail

echo "---- Installing Redis and UFW ----"
apt-get update -y
apt-get install -y redis-server ufw

echo "---- Stopping Redis for reconfiguration ----"
systemctl stop redis-server

echo "---- Configuring Redis for authentication ----"
REDIS_CONF="/etc/redis/redis.conf"

# Backup the original configuration file only once
if [ ! -f "${REDIS_CONF}.orig" ]; then
  cp "${REDIS_CONF}" "${REDIS_CONF}.orig"
fi

# Bind Redis to the private IP only
sed -i "s/^bind .*/bind ${PRIVATE_IP}/" "${REDIS_CONF}"
# Remove any IPv6 binding to avoid listening on ::1
sed -i '/^bind ::1/d' "${REDIS_CONF}"

# Ensure Redis listens on port 6379
sed -i "s/^port .*/port 6379/" "${REDIS_CONF}"

# Remove any active (uncommented) supervised directives
sed -i '/^[[:space:]]*supervised[[:space:]]\+/d' "${REDIS_CONF}"
# Insert a single active "supervised systemd" directive immediately after the port line
sed -i '/^port 6379/ a supervised systemd' "${REDIS_CONF}"

# Disable protected mode (we rely on ACL and firewall for security)
sed -i "s/^protected-mode .*/protected-mode no/" "${REDIS_CONF}"

# Remove any previous ACL configuration block (if exists)
sed -i '/#--- Redis ACL Configuration Start ---/,/#--- Redis ACL Configuration End ---/d' "${REDIS_CONF}"
# Also remove any lingering ACL lines for the default or custom user
sed -i "/^user ${REDIS_USERNAME} /d" "${REDIS_CONF}"
sed -i "/^user default /d" "${REDIS_CONF}"

# Append the new ACL configuration block with markers for idempotency
cat <<EOF >> "${REDIS_CONF}"

#--- Redis ACL Configuration Start ---
user default off
user ${REDIS_USERNAME} on >${REDIS_PASSWORD} ~* +@all
#--- Redis ACL Configuration End ---
EOF

echo "---- Restarting Redis with new configuration ----"
systemctl daemon-reload
systemctl enable redis-server
systemctl restart redis-server

echo "---- Configuring UFW firewall ----"
ufw default deny incoming
ufw default allow outgoing
# Allow SSH from anywhere (port 22)
ufw allow OpenSSH
# Remove any existing Redis rule for the allowed IP (ignore errors if rule does not exist)
ufw delete allow from "${ALLOWED_IP}" to any port 6379 proto tcp 2>/dev/null || true
# Allow Redis port (6379) only from the specified trusted IP
ufw allow from "${ALLOWED_IP}" to any port 6379 proto tcp
ufw --force enable

echo "Setup complete. Redis is running on ${PRIVATE_IP}:6379."
