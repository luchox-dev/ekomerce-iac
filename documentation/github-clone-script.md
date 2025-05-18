# GitHub Repository Clone Script

This document explains the script for cloning GitHub repositories during Terraform provisioning and the solution to SSH authentication issues.

## Problem

The original script encountered SSH authentication failures when running in the EC2 environment, despite working in Docker testing. The key problems were:

1. Environment variables not being properly passed through sudo
2. SSH agent not being initialized properly 
3. Inconsistent SSH options between testing and production

## Solution

We addressed these issues with the following changes:

### 1. Fixed Environment Variable Handling

In `main.tf`, we changed how `GIT_SSH_COMMAND` is set:

```diff
- "GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' sudo -E python3 /tmp/github_repo_clone.py --ssh-dir /home/ubuntu/ssh_keys --dest-dir /opt/app --repo git@github.com:username/repository.git"
+ "export GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes'",
+ "sudo -E python3 /tmp/github_repo_clone.py --ssh-dir /home/ubuntu/ssh_keys --dest-dir /opt/app --repo ${REPOSITORY_URL}"
```

The key change is to export the variable before calling sudo with -E, instead of setting it inline.

### 2. Initialized SSH Agent Properly

Added SSH agent initialization and key loading to ensure keys are available:

```diff
+ "eval $(ssh-agent) && ssh-add /home/ubuntu/ssh_keys/id_ec2_ed25519",
```

### 3. Enhanced Script to Detect and Handle SSH Issues

Made these improvements to `github_repo_clone.py`:

1. Added environment variable logging for debugging
2. Implemented direct SSH testing as a fallback
3. Set `GIT_SSH_COMMAND` consistently throughout the script
4. Applied BatchMode=yes to prevent hanging on any SSH prompts
5. Added verbose logging of environment variables

### 4. Additional Debug Tools

Created a verification function to test direct SSH access to GitHub:

```python
def verify_ssh_works() -> bool:
    """
    Verify that SSH to GitHub works by running a direct command.
    This helps debug SSH environment issues.
    """
    # ... implementation ...
```

## Usage

1. The script can be tested in Docker using the provided `test_ssh_changes.sh` script:
   ```bash
   ./test_ssh_changes.sh
   ```

2. In production, Terraform applies these changes during provisioning.

## Common Issues & Troubleshooting

If you encounter SSH authentication issues:

1. Check that SSH keys have correct permissions (600 for private keys)
2. Verify the key is added to your GitHub account
3. Check environment variables are properly preserved through sudo
4. Ensure SSH agent is running and key is added
5. Look for detailed error messages in the script logs

## Advanced Configuration

For enhanced security in production, you can enable strict host key checking by modifying the `--strict-host-checking` parameter:

```bash
python3 github_repo_clone.py --ssh-dir /path/to/keys --strict-host-checking=true
```