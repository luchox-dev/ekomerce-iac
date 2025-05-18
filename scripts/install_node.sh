#!/usr/bin/env bash
# filepath: install_node.sh

# Script to install a specific Node.js version using nvm

# Check if a version parameter was provided
if [ $# -eq 0 ]; then
  echo "Error: No Node.js version specified."
  echo "Usage: $0 <node_version>"
  echo "Example: $0 16"
  exit 1
fi

NODE_VERSION=$1

echo "Installing Node.js version $NODE_VERSION..."

# Check if curl is installed
if ! command -v curl &> /dev/null; then
  echo "Error: curl is not installed. Please install curl and try again."
  exit 1
fi

# Check for nvm in possible locations and source it
if [ -d "/usr/local/share/nvm" ]; then
  echo "Found nvm in system directory, sourcing it..."
  export NVM_DIR="/usr/local/share/nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
elif [ -d "$HOME/.nvm" ]; then
  echo "Found nvm in home directory, sourcing it..."
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
else
  echo "Installing nvm..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash
  
  # Determine where nvm was installed and source it
  if [ -d "/usr/local/share/nvm" ]; then
    export NVM_DIR="/usr/local/share/nvm"
  else
    export NVM_DIR="$HOME/.nvm"
  fi
  
  # Source nvm
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
fi

# Check if nvm is available
if ! command -v nvm &> /dev/null; then
  echo "Error: nvm is not available."
  echo "Please run the following commands to use it now:"
  echo "export NVM_DIR=\"$NVM_DIR\""
  echo "[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\""
  echo "Then try running this script again."
  exit 1
fi

# Install the specified Node.js version
echo "Installing Node.js version $NODE_VERSION..."
nvm install "$NODE_VERSION"

# Verify installation
if [ $? -ne 0 ]; then
  echo "Error: Failed to install Node.js version $NODE_VERSION"
  exit 1
fi

# Use the installed version
nvm use "$NODE_VERSION"

# Verify Node.js version
echo "Node.js version:"
node -v

# Verify nvm current
echo "nvm current:"
nvm current

# Verify npm version
echo "npm version:"
npm -v

npm install --global npm@latest
npm install --global yarn

echo "Node.js version $NODE_VERSION has been successfully installed!"