#!/bin/bash
# Install Docker on Ubuntu/Debian
set -e

echo "=== Installing Docker ==="

sudo apt update
sudo apt install -y docker.io

# Enable and start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Add current user to docker group
sudo usermod -aG docker "$USER"

echo "=== Docker installed successfully ==="
echo "Log out and back in for group changes to take effect."
docker --version
