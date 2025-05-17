#!/bin/bash
# Test script to validate SSH environment handling in Docker

# Set -e to exit on error
set -e

# Build the Docker image
echo "Building Docker image..."
docker build -t github-clone-test -f Dockerfile.github-clone .

# Run the container with verbose logging and mounted SSH keys
echo "Running container with SSH keys..."
docker run -v ~/.ssh:/app/ssh_keys \
  -e VERBOSE=true \
  --rm -it github-clone-test \
  python3 /app/github_repo_clone.py \
  --ssh-dir /app/ssh_keys \
  --dest-dir /tmp/test-repo \
  --repo git@github.com:luchox-dev/qleber-platform.git \
  --verbose

# Note: The above assumes you have SSH keys in ~/.ssh that can access the repository
# If your keys are elsewhere, modify the volume mount path accordingly