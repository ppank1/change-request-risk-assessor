# Troubleshooting Log

## Incident 1: Docker Permission Denied

**Date:** [To be filled during implementation]

### Symptom
`Got permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock`

### Investigation
- Checked current user groups with `groups` command
- Verified Docker service is running with `systemctl status docker`
- Checked socket permissions with `ls -la /var/run/docker.sock`

### Hypothesis
Current user is not a member of the `docker` group, so cannot access the Docker daemon socket.

### Resolution
```bash
sudo usermod -aG docker $USER
# Log out and back in for group membership to take effect
newgrp docker
```

### Prevention
- Add `usermod -aG docker` to the setup scripts
- Document group membership requirement in onboarding docs

---

## Incident 2: CrashLoopBackOff

**Date:** [To be filled during implementation]

### Symptom
Pod status shows `CrashLoopBackOff` after deployment. `kubectl describe pod` shows repeated restart attempts.

### Investigation
- Checked pod logs: `kubectl logs <pod-name> -n crra-dev`
- Checked pod events: `kubectl describe pod <pod-name> -n crra-dev`
- Reviewed resource limits in deployment.yaml

### Hypothesis
Application is failing to start due to either:
1. Missing environment variables from ConfigMap
2. Insufficient memory allocation causing OOMKilled
3. Health check failing before app is ready

### Resolution
- Verified ConfigMap was applied correctly
- Increased `initialDelaySeconds` on readiness probe to give app time to start
- Checked for import errors in application code

### Prevention
- Ensure ConfigMap is applied before Deployment
- Set appropriate `initialDelaySeconds` values
- Test container locally before deploying: `docker run -p 5000:5000 crra`

---

## Incident 3: ImagePullBackOff

**Date:** [To be filled during implementation]

### Symptom
Pod stuck in `ImagePullBackOff` status. Events show `Failed to pull image`.

### Investigation
- Checked image name in deployment.yaml matches pushed image
- Verified image exists in registry: `docker images`
- Checked imagePullSecrets configuration

### Hypothesis
The image either does not exist in the registry, the tag is wrong, or registry credentials are not configured in the cluster.

### Resolution
- Corrected image tag in deployment.yaml to match the actual pushed tag
- Created imagePullSecret if using private registry:
  ```bash
  kubectl create secret docker-registry regcred --docker-server=<registry> --docker-username=<user> --docker-password=<pass> -n crra-dev
  ```

### Prevention
- Use `latest` tag for dev environments to avoid tag mismatches
- Automate image tag updates in CI/CD pipeline
- Verify image availability before deployment in pipeline
