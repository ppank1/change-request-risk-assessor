#!/bin/bash
# Deploy CRRA to Kubernetes.
# Usage: scripts/deploy.sh <image>   e.g. docker.io/<hub-user>/crra:<commit-sha>
set -e

IMAGE="${1:?usage: deploy.sh <image> -- full reference incl. the commit-SHA tag}"

echo "=== Deploying CRRA ${IMAGE} ==="

# Apply manifests in order
kubectl apply -f k8s/namespace.yaml
echo "Namespaces created."

kubectl apply -f k8s/configmap.yaml
echo "ConfigMap applied."

kubectl apply -f k8s/deployment.yaml
echo "Deployment applied."

kubectl apply -f k8s/service.yaml
echo "Service applied."

# Pin the exact image; the manifest carries only a placeholder tag.
kubectl set image deployment/crra crra="${IMAGE}" -n crra-dev
echo "Image pinned to ${IMAGE}."

# Wait for rollout
echo "Waiting for deployment to be ready..."
kubectl rollout status deployment/crra -n crra-dev --timeout=120s

# Verify health through the Service, the same path real clients take.
# (exec-ing into "the first pod" raced the rolling update: right after a
# rollout that pod is often the OLD one still terminating -> exit 137.)
echo "Verifying health endpoint..."
kubectl run crra-healthcheck -n crra-dev --rm -i --restart=Never --quiet \
  --image="${IMAGE}" --command -- \
  python -c "import urllib.request; print(urllib.request.urlopen('http://crra-service:5000/health', timeout=5).read().decode())"

# Every pod behind the Service must be on the image we just deployed.
echo "Running pods:"
kubectl get pods -n crra-dev -l app=crra --field-selector=status.phase=Running \
  -o custom-columns='POD:.metadata.name,IMAGE:.spec.containers[0].image,READY:.status.containerStatuses[0].ready'
STALE=$(kubectl get pods -n crra-dev -l app=crra --field-selector=status.phase=Running \
  -o jsonpath='{.items[*].spec.containers[0].image}' | tr ' ' '\n' | grep -vc "^${IMAGE}$" || true)
if [ "${STALE}" != "0" ]; then
  echo "ERROR: ${STALE} running pod(s) are not on ${IMAGE}" >&2
  exit 1
fi

echo "=== Deployment complete ==="
