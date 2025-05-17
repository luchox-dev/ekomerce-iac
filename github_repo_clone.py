#!/usr/bin/env python3
"""
GitHub Private Repository Cloning Script for Terraform Provisioning

This script automates the process of cloning a private GitHub repository when provisioning
infrastructure with Terraform. It sets up SSH key authentication, tests the connection,
and handles error conditions appropriately.

Key features:
- SSH key setup with proper permissions
- GitHub host key verification
- Idempotent repository operations (updates if exists, clones if not)
- Comprehensive error handling and logging
- Non-interactive execution suitable for automation

Author: Claude (Improved version)
Date: 2025-05-15
"""

import os
import sys
import logging
import subprocess
import argparse
import glob
import time
import tempfile
import shutil
import re
import traceback
from pathlib import Path
from typing import Tuple, List, Optional, Dict, Any, Union

# Exit codes
EXIT_SUCCESS = 0
EXIT_FAILURE = 1
EXIT_SSH_KEY_ERROR = 2
EXIT_SSH_CONFIG_ERROR = 3
EXIT_GITHUB_CONNECTION_ERROR = 4
EXIT_GIT_CLONE_ERROR = 5
EXIT_GIT_PULL_ERROR = 6
EXIT_PERMISSION_ERROR = 7

# Default values
DEFAULT_SSH_DIR = "ssh_keys"
DEFAULT_DEST_DIR = "/opt/app"
SSH_CONFIG_PATH = "~/.ssh/config"
GITHUB_HOST = "github.com"
MAX_RETRIES = 3
RETRY_DELAY = 5  # seconds
# GitHub SSH URL format: git@github.com:username/repository.git
DEFAULT_REPO = "git@github.com:luchox-dev/qleber-platform.git"  # Will be overridden by command line parameter

# GitHub's known SSH key fingerprints (from https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)
GITHUB_KEY_FINGERPRINTS = {
    "rsa": "SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s",
    "ecdsa": "SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM",
    "ed25519": "SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"
}

# Configure logging with fallback paths
def setup_logging(verbose=False, log_to_file=True) -> None:
    """
    Set up logging with fallback paths for log file.
    
    Args:
        verbose: Enable verbose (DEBUG) logging if True
        log_to_file: Whether to log to a file in addition to stdout
    """
    log_format = '%(asctime)s - %(levelname)s - %(name)s - %(message)s'
    log_level = logging.DEBUG if verbose else logging.INFO
    
    # Define possible log locations in order of preference
    log_paths = [
        "/var/log/github_clone.log",  # System log directory
        os.path.expanduser("~/github_clone.log"),  # User's home directory
        os.path.join(tempfile.gettempdir(), "github_clone.log"),  # System temp directory
        "github_clone.log"  # Current directory
    ]
    
    # Always add stdout handler
    handlers = [logging.StreamHandler(sys.stdout)]
    
    # Try to add file handler with first writable location if log_to_file is True
    if log_to_file:
        for log_path in log_paths:
            try:
                # Try to create log file or check if it's writable
                log_dir = os.path.dirname(log_path)
                if log_dir and not os.path.exists(log_dir):
                    continue  # Skip if directory doesn't exist
                    
                # Test if we can write to this location
                with open(log_path, 'a') as f:
                    pass
                    
                # Add file handler if test passed
                handlers.append(logging.FileHandler(log_path))
                print(f"Logging to: {log_path}")
                break
            except (IOError, PermissionError):
                continue
        
        if len(handlers) == 1 and log_to_file:
            logging.warning("Could not create log file. Logging to stdout only.")
    
    # Configure root logger
    logging.basicConfig(
        level=log_level,
        format=log_format,
        handlers=handlers
    )
    
    # Create and get logger for this module
    logger = logging.getLogger('github_clone')
    
    if verbose:
        logger.info("Verbose logging enabled")

# Initialize logging with default settings
# Will be reconfigured later with command line arguments
setup_logging()
logger = logging.getLogger('github_clone')

def validate_repo_url(url: str) -> bool:
    """
    Validate GitHub SSH repository URL format.
    
    Args:
        url: The repository URL to validate
        
    Returns:
        True if the URL is valid, False otherwise
    """
    if not url:
        return False
    
    # Basic format validation for SSH URL
    if not url.startswith("git@") or ":" not in url:
        return False
    
    # Should have a username and repository name
    parts = url.split(":")
    if len(parts) != 2 or "/" not in parts[1]:
        return False
    
    # Should end with .git
    if not parts[1].endswith(".git"):
        return False
    
    return True

def parse_arguments() -> argparse.Namespace:
    """
    Parse command-line arguments with validation.
    
    Returns:
        Parsed arguments as a Namespace object
    """
    parser = argparse.ArgumentParser(description='Clone a private GitHub repository.')
    parser.add_argument('--repo', type=str, default=DEFAULT_REPO,
                        help=f'GitHub repository URL in SSH format (e.g., git@github.com:username/repo.git)')
    parser.add_argument('--ssh-dir', type=str, default=DEFAULT_SSH_DIR,
                        help=f'Directory containing SSH keys (default: {DEFAULT_SSH_DIR})')
    parser.add_argument('--dest-dir', type=str, default=DEFAULT_DEST_DIR,
                        help=f'Destination directory for the repository (default: {DEFAULT_DEST_DIR})')
    parser.add_argument('--verbose', action='store_true',
                        help='Enable verbose logging')
    parser.add_argument('--force-clone', action='store_true',
                        help='Force fresh clone even if repository exists')
    parser.add_argument('--skip-pull', action='store_true',
                        help='Skip pulling updates if repository exists')
    parser.add_argument('--strict-host-checking', type=lambda x: x.lower() in ['true', 'yes', '1'], default=False,
                        help='Enable strict host key checking (default: False)')
    parser.add_argument('--no-log-file', action='store_true',
                        help='Disable logging to file (log to stdout only)')
    parser.add_argument('--max-backups', type=int, default=3,
                        help='Maximum number of backup directories to keep (default: 3)')
    
    # Environment variable support
    env_repo = os.environ.get('GITHUB_REPO_URL')
    env_ssh_dir = os.environ.get('SSH_KEYS_DIR')
    env_dest_dir = os.environ.get('REPO_DEST_DIR')
    env_skip_clone = os.environ.get('SKIP_CLONE', '').lower() in ('true', 'yes', '1')
    
    # Parse arguments
    args = parser.parse_args()
    
    # Override with environment variables if set
    if env_repo:
        args.repo = env_repo
    if env_ssh_dir:
        args.ssh_dir = env_ssh_dir
    if env_dest_dir:
        args.dest_dir = env_dest_dir
    
    # Special handling for SKIP_CLONE
    if env_skip_clone:
        logger.info("SKIP_CLONE environment variable is set, repository cloning will be simulated")
        # We'll handle this in the main function
    
    # Validate repository URL
    if not validate_repo_url(args.repo):
        parser.error(f"Invalid repository URL format: {args.repo}\n"
                     f"URL must be in the format git@github.com:username/repository.git")
    
    # Validate SSH directory exists
    if not os.path.exists(args.ssh_dir):
        parser.error(f"SSH directory not found: {args.ssh_dir}")
    
    # Convert any relative paths to absolute
    if not os.path.isabs(args.ssh_dir):
        args.ssh_dir = os.path.abspath(args.ssh_dir)
    
    if not os.path.isabs(args.dest_dir):
        args.dest_dir = os.path.abspath(args.dest_dir)
        
    return args

def run_command(
    command: Union[List[str], str], 
    description: Optional[str] = None, 
    shell: bool = False, 
    check: bool = True,
    env: Optional[Dict[str, str]] = None,
    capture_output: bool = True,
    timeout: Optional[int] = None
) -> Tuple[int, str, str]:
    """
    Execute a shell command and log the output.
    
    Args:
        command: Command to execute (list or string)
        description: Description of the command for logging
        shell: Whether to run the command in a shell
        check: Whether to raise an exception on error
        env: Environment variables to set for the command
        capture_output: Whether to capture stdout and stderr
        timeout: Command timeout in seconds
        
    Returns:
        tuple: (return_code, stdout, stderr)
    """
    if description:
        logger.info(f"TASK: {description}")
    
    # Sanitize command for logging (remove sensitive information)
    cmd_str = command if isinstance(command, str) else " ".join(command)
    log_cmd_str = cmd_str
    # Redact potential SSH keys or tokens if found
    if any(keyword in log_cmd_str.lower() for keyword in ['key', 'token', 'password', 'secret']):
        log_cmd_str = re.sub(r'(-i|\s+)[^\s]*(id_|key|\.pem)', r'\1[REDACTED]', log_cmd_str)
    
    logger.info(f"Executing: {log_cmd_str}")
    
    try:
        if shell and isinstance(command, list):
            command = " ".join(command)
        
        # Prepare stdout/stderr handling
        stdout_pipe = subprocess.PIPE if capture_output else None
        stderr_pipe = subprocess.PIPE if capture_output else None
        
        # Execute the command
        process = subprocess.Popen(
            command,
            stdout=stdout_pipe,
            stderr=stderr_pipe,
            shell=shell,
            text=True,
            env=env
        )
        
        # Communicate with the process (with optional timeout)
        stdout, stderr = process.communicate(timeout=timeout)
        
        # Default empty strings if output wasn't captured
        stdout = stdout or ""
        stderr = stderr or ""
        
        # Log stdout and stderr
        if stdout and capture_output:
            for line in stdout.splitlines():
                logger.debug(f"STDOUT: {line}")
        
        if stderr and capture_output:
            for line in stderr.splitlines():
                # SSH key scans and some git operations output to stderr but aren't errors
                if any(term in line for term in ["Warning", "github.com", "remote:", "hint:"]) and not "Error" in line:
                    logger.debug(f"STDERR: {line}")
                else:
                    logger.warning(f"STDERR: {line}")
        
        if process.returncode != 0 and check:
            logger.error(f"Command failed with return code {process.returncode}")
            error_msg = f"Command '{log_cmd_str}' failed with return code {process.returncode}"
            if stderr:
                error_msg += f": {stderr}"
            raise subprocess.CalledProcessError(process.returncode, cmd_str, stdout, stderr)
        
        return process.returncode, stdout, stderr
    except subprocess.TimeoutExpired as e:
        logger.error(f"Command timed out after {timeout} seconds: {log_cmd_str}")
        return 124, "", f"Timeout after {timeout}s"
    except Exception as e:
        logger.error(f"Exception during command execution: {str(e)}")
        logger.debug(f"Exception traceback: {traceback.format_exc()}")
        if check:
            raise
        return 1, "", str(e)

def ensure_ssh_directory() -> str:
    """
    Ensure SSH directory exists and has proper permissions.
    
    Returns:
        Path to the SSH directory
    """
    logger.info("Ensuring SSH directory exists with proper permissions")
    
    ssh_dir = os.path.expanduser("~/.ssh")
    
    # Create directory if it doesn't exist
    os.makedirs(ssh_dir, exist_ok=True)
    
    # Set proper permissions
    try:
        os.chmod(ssh_dir, 0o700)
        logger.info("SSH directory permissions set to 700")
    except Exception as e:
        logger.error(f"Failed to set SSH directory permissions: {str(e)}")
        logger.debug(f"Exception traceback: {traceback.format_exc()}")
        raise RuntimeError(f"Failed to set SSH directory permissions: {str(e)}")
    
    # Create known_hosts file if it doesn't exist
    known_hosts_path = os.path.join(ssh_dir, "known_hosts")
    if not os.path.exists(known_hosts_path):
        try:
            with open(known_hosts_path, 'w') as f:
                pass
            os.chmod(known_hosts_path, 0o600)
            logger.info(f"Created empty known_hosts file at {known_hosts_path}")
        except Exception as e:
            logger.error(f"Failed to create known_hosts file: {str(e)}")
            logger.debug(f"Exception traceback: {traceback.format_exc()}")
            # Non-fatal, continue
    
    return ssh_dir

def find_ssh_keys(ssh_dir: str) -> List[str]:
    """
    Find SSH private keys in the specified directory, validating permissions.
    
    Args:
        ssh_dir: Directory containing SSH keys
        
    Returns:
        List of paths to private key files
    """
    logger.info(f"Searching for SSH keys in {ssh_dir}")
    
    # Expand path if it's relative
    if not os.path.isabs(ssh_dir):
        ssh_dir = os.path.join(os.getcwd(), ssh_dir)
    
    # Check if directory exists
    if not os.path.isdir(ssh_dir):
        logger.error(f"SSH keys directory {ssh_dir} not found")
        raise FileNotFoundError(f"SSH keys directory {ssh_dir} not found")
    
    # Find all private key files (exclude .pub files)
    private_keys = []
    for file_path in glob.glob(os.path.join(ssh_dir, "*")):
        if os.path.isfile(file_path) and not file_path.endswith(".pub"):
            # Check file permissions
            file_stat = os.stat(file_path)
            file_perms = file_stat.st_mode & 0o777
            
            if file_perms & 0o077:  # If anyone but owner has permissions
                logger.warning(f"SSH key {file_path} has insecure permissions: {oct(file_perms)}")
                logger.info(f"Fixing permissions on {file_path}")
                try:
                    os.chmod(file_path, 0o600)
                except Exception as e:
                    logger.warning(f"Could not fix permissions on {file_path}: {str(e)}")
            
            # Basic check to see if this looks like a private key
            try:
                with open(file_path, 'r') as f:
                    content = f.read(1024)  # Read just the beginning of the file
                    if "PRIVATE KEY" in content:
                        private_keys.append(file_path)
                    else:
                        logger.debug(f"Skipping {file_path} - doesn't appear to be a private key")
            except UnicodeDecodeError:
                # Binary file, probably not a private key in PEM format
                logger.debug(f"Skipping binary file {file_path}")
                continue
            except Exception as e:
                logger.warning(f"Error reading {file_path}: {str(e)}")
                continue
    
    if not private_keys:
        logger.error(f"No SSH private keys found in {ssh_dir}")
        raise FileNotFoundError(f"No SSH private keys found in {ssh_dir}. Please add an SSH key with access to GitHub.")
    
    logger.info(f"Found {len(private_keys)} SSH private keys: {', '.join(private_keys)}")
    return private_keys

def setup_ssh_keys(private_keys: List[str], strict_host_checking: bool = True) -> str:
    """
    Set up SSH keys for GitHub authentication with proper security.
    
    Args:
        private_keys: List of paths to private key files
        strict_host_checking: Whether to use strict host key checking
        
    Returns:
        Path to temporary SSH key directory for cleanup
    """
    logger.info("Setting up SSH keys for GitHub authentication")
    
    # Ensure SSH directory exists
    ssh_dir = ensure_ssh_directory()
    temp_keys = []
    temp_ssh_dir = None
    
    try:
        # Create a temporary directory for keys with secure permissions
        temp_ssh_dir = os.path.join(ssh_dir, f"temp_keys_{int(time.time())}")
        os.makedirs(temp_ssh_dir, exist_ok=True)
        os.chmod(temp_ssh_dir, 0o700)
        logger.info(f"Created temporary SSH key directory at {temp_ssh_dir}")
        
        # Copy each private key to the temporary directory
        for key_path in private_keys:
            key_filename = os.path.basename(key_path)
            dest_path = os.path.join(temp_ssh_dir, key_filename)
            temp_keys.append(dest_path)
            
            # Copy the key
            try:
                with open(key_path, 'r') as src_file:
                    key_content = src_file.read()
                    # Basic validation that this is a proper SSH key
                    if "PRIVATE KEY" not in key_content:
                        logger.warning(f"Key file {key_path} may not be a valid private key")
                    with open(dest_path, 'w') as dst_file:
                        dst_file.write(key_content)
                
                # Set proper permissions
                os.chmod(dest_path, 0o600)
                logger.info(f"Copied key {key_path} to {dest_path} with 600 permissions")
            except Exception as e:
                logger.error(f"Failed to copy SSH key {key_path}: {str(e)}")
                logger.debug(f"Exception traceback: {traceback.format_exc()}")
                raise
        
        # Create SSH config file
        config_path = os.path.expanduser(SSH_CONFIG_PATH)
        config_backup = None
        
        # Check if config file exists with GitHub host entry
        github_config_exists = False
        if os.path.exists(config_path):
            try:
                with open(config_path, 'r') as f:
                    content = f.read()
                    github_config_exists = f"Host {GITHUB_HOST}" in content
            except Exception as e:
                logger.warning(f"Could not read SSH config: {str(e)}")

        # Backup existing config if it exists
        if os.path.exists(config_path):
            config_backup = f"{config_path}.bak.{int(time.time())}"
            try:
                with open(config_path, 'r') as src:
                    with open(config_backup, 'w') as dst:
                        dst.write(src.read())
                os.chmod(config_backup, 0o600)
                logger.info(f"Backed up existing SSH config to {config_backup}")
            except Exception as e:
                logger.warning(f"Could not backup SSH config: {str(e)}")
                config_backup = None
        
        # Only modify config if GitHub host is not already configured
        if not github_config_exists:
            # Prepare GitHub-specific configuration
            github_config = (
                f"# GitHub configuration added by github_repo_clone.py at {time.strftime('%Y-%m-%d %H:%M:%S')}\n"
                f"Host {GITHUB_HOST}\n"
                f"  User git\n"
                f"  IdentityFile {os.path.join(temp_ssh_dir, os.path.basename(private_keys[0]))}\n"
                f"  IdentitiesOnly yes\n"  # Only use specified identity file
            )
            
            # Add host key checking configuration
            if strict_host_checking:
                github_config += f"  StrictHostKeyChecking yes\n"
                github_config += f"  VerifyHostKeyDNS yes\n"  # Add additional security
            else:
                github_config += f"  StrictHostKeyChecking no\n"  # Temporarily disable strict host key checking
                github_config += f"  UserKnownHostsFile=/dev/null\n"  # Don't store host keys
                github_config += f"  LogLevel ERROR\n"  # Reduce log noise from SSH
            
            try:
                # If file exists, append to it, otherwise create it
                mode = 'a' if os.path.exists(config_path) else 'w'
                with open(config_path, mode) as f:
                    # Add a blank line for readability if appending
                    if mode == 'a':
                        f.write("\n")
                    f.write(github_config)
                
                # Set proper permissions
                os.chmod(config_path, 0o600)
                logger.info(f"{'Updated' if mode == 'a' else 'Created'} SSH config at {config_path}")
            except Exception as e:
                # Restore backup if we have one
                if config_backup and os.path.exists(config_backup):
                    logger.warning(f"Restoring SSH config backup from {config_backup}")
                    try:
                        shutil.copy2(config_backup, config_path)
                    except Exception as restore_error:
                        logger.error(f"Failed to restore SSH config: {str(restore_error)}")
                logger.error(f"Failed to update SSH config: {str(e)}")
                logger.debug(f"Exception traceback: {traceback.format_exc()}")
                raise RuntimeError(f"Failed to update SSH config: {str(e)}")
        else:
            logger.info(f"GitHub host already configured in SSH config, skipping modification")
        
        return temp_ssh_dir  # Return temp dir for cleanup later
    except Exception as e:
        # Clean up temp directory on error
        if temp_ssh_dir and os.path.exists(temp_ssh_dir):
            logger.info(f"Cleaning up temporary SSH directory after error: {temp_ssh_dir}")
            try:
                for key in temp_keys:
                    if os.path.exists(key):
                        os.remove(key)
                os.rmdir(temp_ssh_dir)
            except Exception as cleanup_error:
                logger.warning(f"Error during cleanup: {str(cleanup_error)}")
        
        logger.error(f"Error in SSH key setup: {str(e)}")
        raise

def add_github_to_known_hosts(strict_host_checking: bool = True) -> bool:
    """
    Add GitHub's SSH key to known_hosts with verification.
    
    Args:
        strict_host_checking: Whether to use strict host key checking
        
    Returns:
        True if successful, False otherwise
    """
    # If strict host checking is disabled and we're using /dev/null as known_hosts file,
    # we can skip this step entirely
    if not strict_host_checking:
        logger.info("Strict host checking is disabled, skipping known_hosts setup")
        return True
        
    logger.info("Adding GitHub's SSH key to known_hosts")
    known_hosts_path = os.path.expanduser("~/.ssh/known_hosts")
    
    try:
        # Check if GitHub is already in known_hosts
        github_in_known_hosts = False
        if os.path.exists(known_hosts_path):
            with open(known_hosts_path, 'r') as f:
                content = f.read()
                github_in_known_hosts = GITHUB_HOST in content
        
        if github_in_known_hosts:
            logger.info(f"GitHub already in {known_hosts_path}, skipping")
            return True
        
        # Get GitHub's SSH key
        returncode, stdout, stderr = run_command(
            ["ssh-keyscan", "-t", "rsa,ecdsa,ed25519", GITHUB_HOST],
            description="Getting GitHub's SSH keys",
            check=False
        )
        
        if returncode != 0:
            logger.warning(f"Failed to get GitHub's SSH keys: {stderr}")
            return False
        
        if not stdout:
            logger.warning("ssh-keyscan returned empty output")
            return False
        
        # Verify keys against known fingerprints if strict host checking
        if strict_host_checking:
            logger.info("Verifying GitHub SSH key fingerprints")
            verified = False
            
            # Get fingerprints from the server key
            for key_type in ["rsa", "ecdsa", "ed25519"]:
                key_lines = [line for line in stdout.splitlines() if f"{GITHUB_HOST} {key_type}" in line]
                if key_lines:
                    key_line = key_lines[0]
                    # Calculate fingerprint
                    try:
                        # Write key to temporary file
                        with tempfile.NamedTemporaryFile(mode='w', delete=False) as temp_key:
                            temp_key.write(key_line)
                            temp_key_path = temp_key.name
                        
                        # Get fingerprint
                        returncode, fp_stdout, fp_stderr = run_command(
                            ["ssh-keygen", "-lf", temp_key_path],
                            description=f"Calculating fingerprint for {key_type} key",
                            check=False
                        )
                        
                        # Clean up temp file
                        try:
                            os.unlink(temp_key_path)
                        except:
                            pass
                        
                        if returncode == 0 and fp_stdout:
                            # Extract SHA256 fingerprint
                            fingerprint = None
                            fp_match = re.search(r'(SHA256:[a-zA-Z0-9+/=]+)', fp_stdout)
                            if fp_match:
                                fingerprint = fp_match.group(1)
                                
                                # Compare with known fingerprint
                                if fingerprint == GITHUB_KEY_FINGERPRINTS.get(key_type):
                                    logger.info(f"Verified {key_type.upper()} key fingerprint: {fingerprint}")
                                    verified = True
                                else:
                                    logger.warning(
                                        f"Key fingerprint mismatch for {key_type.upper()}! "
                                        f"Got {fingerprint}, expected {GITHUB_KEY_FINGERPRINTS.get(key_type)}"
                                    )
                    except Exception as e:
                        logger.warning(f"Error verifying {key_type} key: {str(e)}")
            
            if not verified:
                logger.warning("Could not verify any GitHub SSH key fingerprints!")
                if strict_host_checking:
                    logger.error("Strict host checking is enabled and keys could not be verified. Aborting.")
                    return False
        
        # Add GitHub to known_hosts
        try:
            with open(known_hosts_path, 'a+') as f:
                f.write(stdout)
            # Set proper permissions
            os.chmod(known_hosts_path, 0o600)
            logger.info(f"Added GitHub keys to {known_hosts_path}")
            return True
        except Exception as e:
            logger.error(f"Failed to update known_hosts: {str(e)}")
            logger.debug(f"Exception traceback: {traceback.format_exc()}")
            return False
    except Exception as e:
        logger.error(f"Failed to add GitHub to known_hosts: {str(e)}")
        logger.debug(f"Exception traceback: {traceback.format_exc()}")
        return False

def test_github_connection() -> bool:
    """
    Test SSH connection to GitHub with detailed error handling.
    
    Returns:
        True if successful, False otherwise
    """
    logger.info("Testing SSH connection to GitHub")
    
    # Log environment variables related to SSH for debugging
    for env_var in ['GIT_SSH_COMMAND', 'SSH_AUTH_SOCK', 'SSH_AGENT_PID']:
        logger.info(f"Environment variable {env_var}: {os.environ.get(env_var, 'not set')}")
    
    try:
        # Set the SSH flags for non-interactive use
        ssh_opts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes"
        
        # Use -n flag to prevent reading from stdin
        returncode, stdout, stderr = run_command(
            ["ssh", "-n"] + ssh_opts.split() + ["-T", f"git@{GITHUB_HOST}"],
            description="Testing GitHub SSH connection",
            check=False,
            timeout=30,  # Add timeout to prevent hanging
            env=os.environ.copy()  # Pass through environment variables
        )
        
        # GitHub's successful authentication message comes in stderr
        if "successfully authenticated" in stderr:
            logger.info("Successfully authenticated with GitHub")
            return True
        else:
            # Analyze failure reason
            if "Permission denied" in stderr:
                logger.error("Permission denied by GitHub. Check that your SSH key is registered in your GitHub account.")
            elif "Host key verification failed" in stderr:
                logger.error("Host key verification failed. GitHub's SSH key may have changed.")
            elif "Connection timed out" in stderr:
                logger.error("Connection to GitHub timed out. Check your network connection.")
            else:
                logger.warning(f"Failed to authenticate with GitHub: {stderr}")
            
            return False
    except Exception as e:
        logger.error(f"Error testing GitHub connection: {str(e)}")
        logger.debug(f"Exception traceback: {traceback.format_exc()}")
        return False

def check_git_repo_health(repo_dir: str) -> Tuple[bool, str]:
    """
    Check if a git repository is in a healthy state.
    
    Args:
        repo_dir: Path to the repository directory
        
    Returns:
        Tuple of (is_healthy, error_message)
    """
    logger.info(f"Checking health of git repository at {repo_dir}")
    
    if not os.path.exists(os.path.join(repo_dir, ".git")):
        return False, "Not a git repository"
    
    try:
        # Save original directory
        original_dir = os.getcwd()
        
        try:
            # Change to repo directory
            os.chdir(repo_dir)
            
            # Check git status
            returncode, stdout, stderr = run_command(
                ["git", "status", "--porcelain"],
                description="Checking git status",
                check=False
            )
            
            if returncode != 0:
                return False, f"Git status failed: {stderr}"
            
            # Check if git remote works
            returncode, stdout, stderr = run_command(
                ["git", "remote", "-v"],
                description="Checking git remote",
                check=False
            )
            
            if returncode != 0:
                return False, f"Git remote check failed: {stderr}"
            
            # Try git fetch with timeout
            returncode, stdout, stderr = run_command(
                ["git", "fetch", "--quiet", "--depth=1", "origin"],
                description="Testing git fetch",
                check=False,
                timeout=30
            )
            
            if returncode != 0:
                return False, f"Git fetch failed: {stderr}"
                
            return True, "Repository is healthy"
        finally:
            # Restore original directory
            os.chdir(original_dir)
    except Exception as e:
        logger.error(f"Error checking git repository health: {str(e)}")
        logger.debug(f"Exception traceback: {traceback.format_exc()}")
        return False, str(e)

def clone_repository(
    repo_url: str, 
    dest_dir: str, 
    force_clone: bool = False,
    skip_pull: bool = False,
    max_backups: int = 3
) -> bool:
    """
    Clone the repository to the destination directory with improved idempotence.
    
    Args:
        repo_url: GitHub repository URL
        dest_dir: Destination directory for the repository
        force_clone: Force fresh clone even if repository exists
        skip_pull: Skip pulling updates if repository exists
        max_backups: Maximum number of backup directories to keep
        
    Returns:
        True if successful, False otherwise
    """
    logger.info(f"Processing repository {repo_url} to {dest_dir}")
    
    # Extract repository name from URL for validation
    repo_name = repo_url.split(':')[-1].split('/')[-1]
    if repo_name.endswith('.git'):
        repo_name = repo_name[:-4]
        
    logger.info(f"Repository name: {repo_name}")
    
    # Create parent directory if it doesn't exist
    parent_dir = os.path.dirname(dest_dir)
    if parent_dir and not os.path.exists(parent_dir):
        try:
            os.makedirs(parent_dir, exist_ok=True)
            logger.info(f"Created parent directory: {parent_dir}")
        except Exception as e:
            logger.error(f"Failed to create parent directory {parent_dir}: {str(e)}")
            logger.debug(f"Exception traceback: {traceback.format_exc()}")
            return False
    
    # Check for SKIP_CLONE environment variable
    if os.environ.get('SKIP_CLONE', '').lower() in ('true', 'yes', '1'):
        logger.info("SKIP_CLONE environment variable is set, skipping actual clone operation")
        if not os.path.exists(dest_dir):
            try:
                os.makedirs(dest_dir, exist_ok=True)
                with open(os.path.join(dest_dir, "SIMULATED_CLONE.txt"), 'w') as f:
                    f.write(f"Simulated clone of {repo_url} at {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
                logger.info(f"Created simulation directory at {dest_dir}")
            except Exception as e:
                logger.error(f"Failed to create simulation directory: {str(e)}")
                return False
        return True
    
    # Check if directory already contains a Git repository
    if os.path.exists(os.path.join(dest_dir, ".git")) and not force_clone:
        logger.info(f"Destination {dest_dir} already contains a Git repository")
        
        # Check repository health
        is_healthy, health_message = check_git_repo_health(dest_dir)
        if not is_healthy:
            logger.warning(f"Existing repository is not healthy: {health_message}")
            if force_clone:
                logger.info("Force clone is enabled, will clone fresh")
                return _fresh_clone(repo_url, dest_dir, max_backups)
        
        try:
            # Save original directory
            original_dir = os.getcwd()
            
            try:
                # Change to repository directory
                os.chdir(dest_dir)
                
                # Validate that this is the expected repository
                returncode, stdout, stderr = run_command(
                    ["git", "remote", "-v"],
                    description="Checking remote repository",
                    check=False
                )
                
                if returncode != 0:
                    logger.error(f"Failed to check remote repository: {stderr}")
                    logger.warning("Cannot verify existing repository. Will attempt to remove and clone fresh.")
                    return _fresh_clone(repo_url, dest_dir, max_backups)
                    
                # Check if the remote matches our expected repository
                expected_remote_pattern = re.escape(repo_url)
                if not re.search(expected_remote_pattern, stdout) and repo_name not in stdout:
                    logger.warning(f"Existing repository does not match expected URL {repo_url}")
                    logger.info(f"Found remotes: {stdout.strip()}")
                    
                    # Backup the existing repository
                    backup_dir = f"{dest_dir}_backup_{int(time.time())}"
                    logger.info(f"Backing up existing repository to {backup_dir}")
                    try:
                        if os.path.exists(backup_dir):
                            logger.warning(f"Backup directory {backup_dir} already exists")
                            backup_dir = f"{dest_dir}_backup_{int(time.time())}_{os.getpid()}"
                            logger.info(f"Using alternative backup directory: {backup_dir}")
                            
                        shutil.move(dest_dir, backup_dir)
                        logger.info(f"Successfully backed up existing repository")
                        
                        # Clean up old backups if needed
                        _cleanup_old_backups(dest_dir, max_backups)
                        
                        return _fresh_clone(repo_url, dest_dir, max_backups)
                    except Exception as e:
                        logger.error(f"Failed to backup existing repository: {str(e)}")
                        logger.debug(f"Exception traceback: {traceback.format_exc()}")
                        return False
                
                # If skip_pull is enabled, skip the update
                if skip_pull:
                    logger.info("Skip-pull enabled, not updating existing repository")
                    return True
                
                # Repository matches, pull latest changes
                logger.info(f"Existing repository matches expected. Pulling latest changes.")
                
                # Fetch all branches and tags
                returncode, stdout, stderr = run_command(
                    ["git", "fetch", "--all", "--tags", "--prune", "--quiet"],
                    description="Fetching latest changes",
                    check=False
                )
                
                if returncode != 0:
                    logger.warning(f"Failed to fetch latest changes: {stderr}")
                    # Continue anyway, as local repo might still be usable
                
                # Get current branch
                returncode, stdout, stderr = run_command(
                    ["git", "branch", "--show-current"],
                    description="Getting current branch",
                    check=False
                )
                
                current_branch = stdout.strip()
                default_branch = _get_default_branch()
                
                if not current_branch:
                    # No branch is currently checked out (detached HEAD)
                    current_branch = default_branch
                    logger.warning(f"No branch currently checked out. Using default branch '{current_branch}'")
                    
                    # Try to check out the default branch
                    returncode, stdout, stderr = run_command(
                        ["git", "checkout", current_branch],
                        description=f"Checking out {current_branch} branch",
                        check=False
                    )
                    
                    if returncode != 0:
                        logger.error(f"Failed to check out {current_branch} branch: {stderr}")
                        return False
                
                # Verify the branch exists remotely
                returncode, stdout, stderr = run_command(
                    ["git", "rev-parse", "--verify", f"origin/{current_branch}"],
                    description=f"Verifying branch {current_branch} exists remotely",
                    check=False
                )
                
                if returncode != 0:
                    logger.warning(f"Branch {current_branch} doesn't exist on remote or isn't tracking a remote branch")
                    logger.info(f"Will try to use default branch instead")
                    current_branch = default_branch
                
                # Pull latest changes
                returncode, stdout, stderr = run_command(
                    ["git", "pull", "--ff-only", "origin", current_branch],
                    description=f"Pulling latest changes for branch {current_branch}",
                    check=False
                )
                
                if returncode != 0:
                    logger.error(f"Failed to pull latest changes: {stderr}")
                    
                    # Try to reset to origin/branch as a fallback
                    logger.info(f"Attempting to reset to origin/{current_branch} as fallback")
                    reset_code, reset_stdout, reset_stderr = run_command(
                        ["git", "reset", "--hard", f"origin/{current_branch}"],
                        description=f"Resetting to origin/{current_branch}",
                        check=False
                    )
                    
                    if reset_code != 0:
                        logger.error(f"Failed to reset to origin/{current_branch}: {reset_stderr}")
                        logger.warning("Will attempt to remove and clone fresh.")
                        return _fresh_clone(repo_url, dest_dir, max_backups)
                    else:
                        logger.info(f"Successfully reset to origin/{current_branch}")
                else:
                    logger.info(f"Successfully pulled latest changes for branch {current_branch}")
                
                return True
            finally:
                # Restore original directory
                os.chdir(original_dir)
        except Exception as e:
            logger.error(f"Error processing existing repository: {str(e)}")
            logger.debug(f"Exception traceback: {traceback.format_exc()}")
            return False
    else:
        # No existing repository or force_clone enabled, do a fresh clone
        return _fresh_clone(repo_url, dest_dir, max_backups)

def _get_default_branch() -> str:
    """
    Get the default branch name for the current repository.
    
    Returns:
        Default branch name (main or master)
    """
    try:
        # Try to get the symbolic-ref of HEAD
        returncode, stdout, stderr = run_command(
            ["git", "symbolic-ref", "refs/remotes/origin/HEAD"],
            description="Getting default branch",
            check=False
        )
        
        if returncode == 0 and stdout:
            # Extract branch name from refs/remotes/origin/HEAD
            branch = stdout.strip().split('/')[-1]
            logger.info(f"Detected default branch: {branch}")
            return branch
    except Exception as e:
        logger.debug(f"Error getting default branch: {str(e)}")
    
    # Fallback to trying main, then master
    try:
        for branch in ["main", "master"]:
            returncode, stdout, stderr = run_command(
                ["git", "rev-parse", "--verify", f"origin/{branch}"],
                description=f"Checking if {branch} exists",
                check=False
            )
            
            if returncode == 0:
                logger.info(f"Using {branch} as default branch")
                return branch
    except Exception:
        pass
    
    # Ultimate fallback
    logger.warning("Could not determine default branch, using 'main' as fallback")
    return "main"

def _cleanup_old_backups(base_dir: str, max_backups: int) -> None:
    """
    Clean up old backup directories to save disk space.
    
    Args:
        base_dir: Base directory name (without _backup suffix)
        max_backups: Maximum number of backup directories to keep
    """
    if max_backups <= 0:
        logger.info("Backup cleanup disabled (max_backups <= 0)")
        return
    
    logger.info(f"Cleaning up old backup directories (keeping at most {max_backups})")
    
    try:
        # Get parent directory
        parent_dir = os.path.dirname(base_dir)
        base_name = os.path.basename(base_dir)
        
        # Find all backup directories
        backup_pattern = f"{base_name}_backup_*"
        backup_dirs = []
        
        for item in glob.glob(os.path.join(parent_dir, backup_pattern)):
            if os.path.isdir(item):
                # Get modification time for sorting
                backup_dirs.append((item, os.path.getmtime(item)))
        
        # Sort by modification time (newest first)
        backup_dirs.sort(key=lambda x: x[1], reverse=True)
        
        # Remove oldest backups if we have too many
        if len(backup_dirs) > max_backups:
            for dir_path, _ in backup_dirs[max_backups:]:
                logger.info(f"Removing old backup directory: {dir_path}")
                try:
                    shutil.rmtree(dir_path)
                except Exception as e:
                    logger.warning(f"Failed to remove backup directory {dir_path}: {str(e)}")
    except Exception as e:
        logger.warning(f"Error during backup cleanup: {str(e)}")
        logger.debug(f"Exception traceback: {traceback.format_exc()}")
        # Non-fatal, continue

def _fresh_clone(repo_url: str, dest_dir: str, max_backups: int = 3) -> bool:
    """
    Helper function to perform a fresh clone with retries.
    
    Args:
        repo_url: GitHub repository URL
        dest_dir: Destination directory for the repository
        max_backups: Maximum number of backup directories to keep
        
    Returns:
        True if successful, False otherwise
    """
    logger.info(f"Preparing for fresh clone to {dest_dir}")
    
    # Ensure the destination directory doesn't exist or is empty
    if os.path.exists(dest_dir):
        try:
            if os.path.isdir(dest_dir):
                # Check if directory is empty
                if os.listdir(dest_dir):
                    # Move or remove existing directory
                    backup_dir = f"{dest_dir}_old_{int(time.time())}"
                    logger.info(f"Moving existing directory to {backup_dir}")
                    
                    if os.path.exists(backup_dir):
                        logger.warning(f"Backup directory {backup_dir} already exists")
                        backup_dir = f"{dest_dir}_old_{int(time.time())}_{os.getpid()}"
                        logger.info(f"Using alternative backup directory: {backup_dir}")
                    
                    shutil.move(dest_dir, backup_dir)
                    
                    # Clean up old backups
                    _cleanup_old_backups(dest_dir, max_backups)
            else:
                # It's a file, remove it
                logger.info(f"Removing existing file at {dest_dir}")
                os.remove(dest_dir)
        except Exception as e:
            logger.error(f"Failed to prepare destination directory: {str(e)}")
            logger.debug(f"Exception traceback: {traceback.format_exc()}")
            return False
    
    # For multi-stage clone, only retry the final fetch/pull command
    try:
        # Instead of git clone, use git init and git remote to avoid SSH issues
        if not os.path.exists(dest_dir):
            os.makedirs(dest_dir, exist_ok=True)
        
        # Change to the destination directory
        current_dir = os.getcwd()
        os.chdir(dest_dir)
        
        try:
            # Initialize git repo (only once)
            run_command(
                ["git", "init"],
                description="Initializing git repository",
                check=True
            )
            
            # Check if origin remote already exists
            ret, stdout, stderr = run_command(
                ["git", "remote"],
                description="Checking existing remotes",
                check=False
            )
            
            if "origin" not in stdout:
                # Add origin remote (only if it doesn't exist)
                run_command(
                    ["git", "remote", "add", "origin", repo_url],
                    description="Adding remote origin",
                    check=True
                )
            else:
                # Update the remote URL if it exists but needs updating
                run_command(
                    ["git", "remote", "set-url", "origin", repo_url],
                    description="Updating remote origin URL",
                    check=True
                )
            
            # Set SSH command directly for git command (used in all attempts)
            git_ssh_command = 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes'
            git_env = os.environ.copy()
            # Always set this environment variable to ensure consistent behavior
            git_env['GIT_SSH_COMMAND'] = git_ssh_command
            logger.info(f"Setting GIT_SSH_COMMAND environment variable: {git_ssh_command}")
            
            # Retry only the fetch step which might have connectivity issues
            for attempt in range(1, MAX_RETRIES + 1):
                try:
                    # Fetch everything from origin
                    run_command(
                        ["git", "fetch", "--all"],
                        description=f"Fetching repository content (attempt {attempt}/{MAX_RETRIES})",
                        check=True,
                        timeout=300,  # 5 minute timeout for fetch
                        env=git_env
                    )
                    # If we get here, fetch succeeded
                    break
                except Exception as e:
                    logger.error(f"Failed to fetch repository content (attempt {attempt}/{MAX_RETRIES}): {str(e)}")
                    if attempt < MAX_RETRIES:
                        logger.info(f"Retrying in {RETRY_DELAY} seconds...")
                        time.sleep(RETRY_DELAY)
                    else:
                        raise
                
            # Get default branch
            ret, stdout, stderr = run_command(
                ["git", "remote", "show", "origin"],
                description="Getting default branch",
                check=False,
                env=git_env
            )
            
            # Parse default branch from output
            default_branch = "main"  # Default fallback
            if ret == 0:
                for line in stdout.splitlines():
                    if "HEAD branch" in line:
                        default_branch = line.split(":")[-1].strip()
                        break
            else:
                logger.warning(f"Could not determine default branch, using '{default_branch}' as fallback")
            
            # Checkout the default branch
            try:
                run_command(
                    ["git", "checkout", "-b", default_branch, f"origin/{default_branch}"],
                    description=f"Checking out {default_branch}",
                    check=True,
                    env=git_env
                )
            except Exception as checkout_error:
                # If branch already exists, try a different approach
                if "already exists" in str(checkout_error):
                    try:
                        run_command(
                            ["git", "checkout", default_branch],
                            description=f"Checking out existing {default_branch} branch",
                            check=True,
                            env=git_env
                        )
                        # Pull latest changes
                        run_command(
                            ["git", "pull", "origin", default_branch],
                            description=f"Pulling latest changes for {default_branch}",
                            check=True,
                            env=git_env
                        )
                    except Exception as e:
                        logger.error(f"Failed to checkout existing branch: {str(e)}")
                        # Last resort: force checkout
                        run_command(
                            ["git", "checkout", "-f", default_branch],
                            description=f"Force checkout of {default_branch}",
                            check=True,
                            env=git_env
                        )
                else:
                    raise
        finally:
            # Return to original directory
            os.chdir(current_dir)
            
        logger.info(f"Successfully cloned repository to {dest_dir}")
        
        # Verify the clone was successful by checking for essential files
        if not os.path.exists(os.path.join(dest_dir, ".git")):
            logger.error(f"Clone appeared to succeed but .git directory is missing")
            return False
        
        return True
    
    except subprocess.TimeoutExpired as timeout_error:
        logger.error(f"Clone operation timed out: {str(timeout_error)}")
        logger.error(f"Clone timed out")
        return False
    
    except Exception as e:
        logger.error(f"Failed to clone repository: {str(e)}")
        logger.debug(f"Exception traceback: {traceback.format_exc()}")
        logger.error(f"Failed to clone repository")
        return False
    
    # Should never reach here, but just in case
    return False

def verify_ssh_works() -> bool:
    """
    Verify that SSH to GitHub works by running a direct command.
    This helps debug SSH environment issues.
    
    Returns:
        bool: True if SSH connection works, False otherwise
    """
    logger.info("Verifying direct SSH connection to GitHub")
    
    # Use a direct SSH command to test GitHub access
    env = os.environ.copy()
    ssh_command = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -T git@github.com"
    
    try:
        # Run the command directly through shell for accurate environment
        returncode, stdout, stderr = run_command(
            ssh_command,
            description="Direct SSH test to GitHub",
            shell=True,
            check=False
        )
        
        if "successfully authenticated" in stderr:
            logger.info("Direct SSH connection to GitHub successful")
            return True
        else:
            logger.error(f"Direct SSH connection failed: {stderr}")
            return False
    except Exception as e:
        logger.error(f"Error in direct SSH verification: {str(e)}")
        return False

def main() -> int:
    """
    Main function to orchestrate the repository cloning process.
    
    Returns:
        Exit code (0 for success, non-zero for failure)
    """
    try:
        args = parse_arguments()
        
        # Reconfigure logging with verbose flag
        setup_logging(args.verbose, not args.no_log_file)
        
        repo_url = args.repo
        ssh_dir = args.ssh_dir
        dest_dir = args.dest_dir
        force_clone = args.force_clone
        skip_pull = args.skip_pull
        strict_host_checking = args.strict_host_checking
        max_backups = args.max_backups
        
        # Log environment variables for debugging
        logger.debug("Current environment variables:")
        for key, value in sorted(os.environ.items()):
            if not any(secret in key.lower() for secret in ['key', 'token', 'password', 'secret']):
                logger.debug(f"  {key}={value}")
        
        # Script header
        logger.info("=" * 80)
        logger.info(f"Starting GitHub repository cloning process")
        logger.info(f"Repository URL: {repo_url}")
        logger.info(f"SSH keys directory: {ssh_dir}")
        logger.info(f"Destination directory: {dest_dir}")
        if args.verbose:
            logger.info(f"Verbose mode: Enabled")
        if force_clone:
            logger.info(f"Force clone: Enabled")
        if skip_pull:
            logger.info(f"Skip pull: Enabled")
        if not strict_host_checking:
            logger.info(f"Strict host checking: Disabled")
        logger.info("=" * 80)
        
        temp_ssh_dir = None
        
        try:
            # Find SSH keys
            logger.info("STEP 1: Finding and validating SSH keys")
            private_keys = find_ssh_keys(ssh_dir)
            logger.info("Successfully found SSH keys")
            
            # Set up SSH keys with improved security
            logger.info("STEP 2: Setting up SSH keys for authentication")
            temp_ssh_dir = setup_ssh_keys(private_keys, strict_host_checking)
            logger.info("SSH keys setup completed successfully")
            
            # Add GitHub to known_hosts
            logger.info("STEP 3: Adding GitHub to known_hosts")
            host_key_success = add_github_to_known_hosts(strict_host_checking)
            if not host_key_success and strict_host_checking:
                logger.error("Failed to add GitHub to known_hosts with verification")
                return EXIT_SSH_CONFIG_ERROR
            
            # Test GitHub connection
            logger.info("STEP 4: Testing GitHub SSH connection")
            connection_successful = test_github_connection()
            if not connection_successful:
                logger.warning("GitHub connection test failed")
                
                # Try direct SSH verification as a fallback
                logger.info("Attempting direct SSH verification as fallback")
                direct_ssh_works = verify_ssh_works()
                
                if direct_ssh_works:
                    logger.info("Direct SSH connection works, proceeding despite test failure")
                    connection_successful = True
                elif strict_host_checking:
                    logger.error("Aborting due to failed GitHub connection test with strict host checking enabled")
                    return EXIT_GITHUB_CONNECTION_ERROR
                else:
                    logger.warning("Continuing with cloning attempt despite connection test failure")
            else:
                logger.info("GitHub connection test successful")
            
            # Clone repository
            logger.info("STEP 5: Cloning or updating repository")
            clone_successful = clone_repository(
                repo_url, 
                dest_dir, 
                force_clone=force_clone,
                skip_pull=skip_pull,
                max_backups=max_backups
            )
            
            if clone_successful:
                logger.info("=" * 80)
                logger.info(f"Successfully processed repository {repo_url} to {dest_dir}")
                logger.info("=" * 80)
                return EXIT_SUCCESS
            else:
                logger.error("=" * 80)
                logger.error(f"Failed to process repository {repo_url}")
                logger.error("=" * 80)
                return EXIT_GIT_CLONE_ERROR
        except FileNotFoundError as e:
            logger.error("=" * 80)
            logger.error(f"File not found: {str(e)}")
            logger.error("=" * 80)
            return EXIT_FAILURE
        except PermissionError as e:
            logger.error("=" * 80)
            logger.error(f"Permission denied: {str(e)}")
            logger.error("=" * 80)
            return EXIT_PERMISSION_ERROR
        except Exception as e:
            logger.error("=" * 80)
            logger.error(f"An error occurred: {str(e)}")
            logger.debug(f"Exception traceback: {traceback.format_exc()}")
            logger.error("=" * 80)
            return EXIT_FAILURE
        finally:
            # Clean up temporary resources
            if temp_ssh_dir and os.path.exists(temp_ssh_dir):
                try:
                    logger.info(f"Cleaning up temporary SSH directory {temp_ssh_dir}")
                    
                    # Remove individual key files first
                    for key_file in glob.glob(os.path.join(temp_ssh_dir, "*")):
                        try:
                            os.remove(key_file)
                        except Exception as e:
                            logger.warning(f"Failed to remove key file {key_file}: {str(e)}")
                    
                    # Then remove the directory
                    os.rmdir(temp_ssh_dir)
                except Exception as cleanup_error:
                    logger.warning(f"Failed to clean up temporary directory: {str(cleanup_error)}")
            
            # Restore original SSH config if it was backed up
            ssh_config = os.path.expanduser(SSH_CONFIG_PATH)
            config_backup_pattern = f"{ssh_config}.bak.*"
            for backup_file in glob.glob(config_backup_pattern):
                try:
                    logger.info(f"Removing SSH config backup {backup_file}")
                    os.remove(backup_file)
                except Exception as e:
                    logger.warning(f"Failed to remove SSH config backup: {str(e)}")
            
            logger.info(f"Finished GitHub repository cloning process")
    except Exception as e:
        # Handle any unexpected exceptions in the main function itself
        print(f"Critical error: {str(e)}")
        print(f"Traceback: {traceback.format_exc()}")
        return EXIT_FAILURE

if __name__ == "__main__":
    sys.exit(main())