#!/bin/bash
# Install k3s lightweight Kubernetes
set -e

echo "=== Installing k3s ==="

curl -sfL https://get.k3s.io | sh -

# Wait for k3s to be ready
sleep 10

# Verify installation
sudo kubectl get nodes

# Set up kubeconfig for current user
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$USER:$USER" "$HOME/.kube/config"

echo "=== k3s installed successfully ==="
kubectl get nodes
