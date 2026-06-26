#!/bin/bash
# Deploy CRRA to Kubernetes
set -e

echo "=== Deploying CRRA ==="

# Apply manifests in order
kubectl apply -f k8s/namespace.yaml
echo "Namespaces created."

kubectl apply -f k8s/configmap.yaml
echo "ConfigMap applied."

kubectl apply -f k8s/deployment.yaml
echo "Deployment applied."

kubectl apply -f k8s/service.yaml
echo "Service applied."

# Wait for rollout
echo "Waiting for deployment to be ready..."
kubectl rollout status deployment/crra -n crra-dev --timeout=120s

# Verify health
echo "Verifying health endpoint..."
POD=$(kubectl get pods -n crra-dev -l app=crra -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n crra-dev "$POD" -- python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:5000/health').read().decode())"

echo "=== Deployment complete ==="
