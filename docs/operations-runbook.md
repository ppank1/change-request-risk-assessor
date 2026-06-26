# Operations Runbook

## Health Checks

### Application Health
```bash
# Local
curl http://localhost:5000/health

# In Kubernetes
kubectl exec -n crra-dev deploy/crra -- python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:5000/health').read().decode())"

# Via port-forward
kubectl port-forward -n crra-dev svc/crra-service 5000:5000
curl http://localhost:5000/health
```

Expected response:
```json
{"status": "healthy", "version": "1.0.0", "scoring_strategy": "simple"}
```

### Kubernetes Health
```bash
kubectl get pods -n crra-dev
kubectl get deployment crra -n crra-dev
kubectl describe pod -n crra-dev -l app=crra
```

## Scaling

### Manual Scaling
```bash
# Scale up
kubectl scale deployment crra -n crra-dev --replicas=4

# Scale down
kubectl scale deployment crra -n crra-dev --replicas=2
```

### Verify Scaling
```bash
kubectl get pods -n crra-dev -l app=crra
kubectl rollout status deployment/crra -n crra-dev
```

## Rollback Procedure

### Rollback to Previous Version
```bash
# View rollout history
kubectl rollout history deployment/crra -n crra-dev

# Rollback to previous revision
kubectl rollout undo deployment/crra -n crra-dev

# Rollback to specific revision
kubectl rollout undo deployment/crra -n crra-dev --to-revision=2

# Verify rollback
kubectl rollout status deployment/crra -n crra-dev
```

### Docker Image Rollback
```bash
# Update deployment to use a previous image tag
kubectl set image deployment/crra crra=docker.io/crra:<previous-tag> -n crra-dev
```

## Log Access

### Application Logs
```bash
# All pods
kubectl logs -n crra-dev -l app=crra

# Specific pod
kubectl logs -n crra-dev <pod-name>

# Follow logs in real time
kubectl logs -n crra-dev -l app=crra -f

# Previous container (after crash)
kubectl logs -n crra-dev <pod-name> --previous
```

### Jenkins Logs
```bash
sudo journalctl -u jenkins -f
# Or via Jenkins UI: Manage Jenkins → System Log
```

## Common Issues

### Issue: Pods Not Starting
**Symptoms**: Pods in Pending or CrashLoopBackOff state

**Diagnosis**:
```bash
kubectl describe pod -n crra-dev -l app=crra
kubectl get events -n crra-dev --sort-by='.lastTimestamp'
```

**Resolution**:
- Check resource availability: `kubectl describe nodes`
- Check ConfigMap exists: `kubectl get configmap -n crra-dev`
- Check image availability: verify image tag matches pushed image

### Issue: Service Not Reachable
**Symptoms**: Connection refused or timeout when accessing service

**Diagnosis**:
```bash
kubectl get svc -n crra-dev
kubectl get endpoints -n crra-dev
kubectl describe svc crra-service -n crra-dev
```

**Resolution**:
- Verify selector labels match pod labels
- Check pods are in Ready state
- Verify port configuration matches container port

### Issue: Configuration Changes Not Applied
**Symptoms**: Application behaviour does not reflect ConfigMap changes

**Diagnosis**:
```bash
kubectl get configmap crra-config -n crra-dev -o yaml
kubectl describe pod -n crra-dev -l app=crra | grep -A 10 "Environment"
```

**Resolution**:
- ConfigMap changes require pod restart to take effect:
  ```bash
  kubectl rollout restart deployment/crra -n crra-dev
  ```

### Issue: High Memory Usage
**Symptoms**: OOMKilled events or pod restarts

**Diagnosis**:
```bash
kubectl top pods -n crra-dev
kubectl describe pod <pod-name> -n crra-dev | grep -A 5 "Last State"
```

**Resolution**:
- Increase memory limits in deployment.yaml
- Investigate memory leaks in application
- Reduce gunicorn worker count
