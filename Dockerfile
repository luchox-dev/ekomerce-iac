FROM ubuntu:24.04

# Avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Update and install basic utilities
RUN apt-get update && \
    apt-get install -y \
    sudo \
    python3 \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy the script
COPY letsencrypt_wildcard_setup.py /usr/local/bin/
RUN chmod +x /usr/local/bin/letsencrypt_wildcard_setup.py

# Default command - this will check the script for syntax errors
CMD ["python3", "-m", "py_compile", "/usr/local/bin/letsencrypt_wildcard_setup.py"]