# GitHub Repository Clone Docker Service

This Docker service provides a reliable way to clone private GitHub repositories using SSH authentication, particularly useful for automated deployment processes and CI/CD pipelines.

## Overview

The GitHub Clone Docker service is designed to:

1. Securely clone private GitHub repositories using SSH
2. Handle SSH authentication edge cases in automated environments
3. Provide built-in testing and validation for the cloning process
4. Support robust error handling for deployment scenarios

## Docker Image Details

- **Base Image**: Ubuntu 24.04
- **Installed Packages**: python3, python3-pip, git, openssh-client, curl, sudo
- **Primary Script**: github_repo_clone.py

## Building the Image

```bash
# From the repository root
docker build -t github-clone-service -f docker/Dockerfile.github-clone .
```

## Usage

### Basic Usage

When you run the container with no arguments, it will run validation tests and show usage instructions:

```bash
docker run --rm -it github-clone-service
```

### Using with Your SSH Keys

To clone a repository with your SSH keys:

```bash
docker run -v /path/to/your/ssh/keys:/app/ssh_keys --rm -it github-clone-service \
  python3 /app/github_repo_clone.py \
  --ssh-dir /app/ssh_keys \
  --dest-dir /opt/app \
  --repo git@github.com:username/repository.git
```

### Script Options

The `github_repo_clone.py` script accepts the following parameters:

- `--ssh-dir`: Directory containing SSH keys (required)
- `--dest-dir`: Destination directory for cloned repository (required)
- `--repo`: Git repository SSH URL (required)
- `--strict-host-checking`: Whether to enable strict host key checking (default: true)
- `--branch`: Specific branch to clone (optional)
- `--ssh-key-name`: Custom SSH key filename (default: id_rsa or id_ed25519)
- `--help`: Show help message

## Common Use Cases

### CI/CD Pipeline Integration

```bash
docker run --rm \
  -v /path/to/deployment/keys:/app/ssh_keys \
  github-clone-service \
  python3 /app/github_repo_clone.py \
  --ssh-dir /app/ssh_keys \
  --dest-dir /opt/app \
  --repo git@github.com:username/repository.git \
  --branch production
```

### Testing SSH Connectivity

Use the built-in verification function to test if SSH is properly configured:

```bash
# Inside the container
python3 -c "import sys; sys.path.append('/app'); from github_repo_clone import verify_ssh_works; print(verify_ssh_works())"
```

## Troubleshooting

If you encounter issues with SSH authentication:

1. Check that SSH keys have correct permissions (600 for private keys)
2. Verify the key is added to your GitHub account
3. Check environment variables are properly preserved when using sudo
4. Ensure SSH agent is running and key is added
5. Look for detailed error messages in the script logs

## Advanced Configuration

### Disabling Strict Host Key Checking

For environments where you cannot save known hosts:

```bash
docker run -v /path/to/your/ssh/keys:/app/ssh_keys --rm -it github-clone-service \
  python3 /app/github_repo_clone.py \
  --ssh-dir /app/ssh_keys \
  --dest-dir /opt/app \
  --repo git@github.com:username/repository.git \
  --strict-host-checking=false
```

### Using a Custom SSH Key Name

If your SSH key isn't named `id_rsa` or `id_ed25519`:

```bash
docker run -v /path/to/your/ssh/keys:/app/ssh_keys --rm -it github-clone-service \
  python3 /app/github_repo_clone.py \
  --ssh-dir /app/ssh_keys \
  --dest-dir /opt/app \
  --repo git@github.com:username/repository.git \
  --ssh-key-name my_custom_key
```

## Security Considerations

- SSH private keys are sensitive and should be handled securely
- Consider using secrets management for production deployments
- When using Docker volumes, ensure proper file system permissions

## See Also

- [GitHub Clone Script Guide](../README-github-clone-script.md)
- [SSH Setup for EC2 Deployments](../clone_github_repo_guide.txt)