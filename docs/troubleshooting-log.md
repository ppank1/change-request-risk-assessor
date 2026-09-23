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

---

## Incident 4: Prometheus target DOWN — `dial tcp 172.31.37.73:9100: i/o timeout`

**Date:** 2026-09-23

### Symptom
After the first `site.yml` run installed Prometheus, the Targets page showed `node (1/2 up)`: the `crra-k3s-001` node_exporter target was DOWN with `Get "http://172.31.37.73:9100/metrics": dial tcp 172.31.37.73:9100: i/o timeout`. The Jenkins-host node target and the app target (`:30000`) were UP. `TargetDown` alert went to FIRING after 2 minutes.

### Investigation
Three checks, each ruling out one layer, all from the devdesk over the SSM tunnel (no SSH):
1. On the k3s host: `systemctl is-active node_exporter` → `active`; `ss -ltn | grep 9100` → `LISTEN *:9100`; `curl localhost:9100/metrics` → metrics served. **Service fine.**
2. From the Jenkins host: `curl -m 3 http://172.31.37.73:9100/metrics` → `000 / TIMEOUT`. **Path blocked** (a timeout, not a refusal — nothing is answering the SYN, which points at a firewall rather than the process).
3. `aws ec2 describe-security-group-rules` on `crra-k3s-sg` filtered to source `172.31.46.173/32` (Jenkins) → only `6443` (k8s API) and `30000` (app scrape). **No rule for 9100.**

### Hypothesis
The k3s security group allows the Jenkins host to reach the Kubernetes API and the app NodePort, but the node_exporter scrape port was never opened when the monitoring role was added.

### Resolution
Added `aws_vpc_security_group_ingress_rule.k3s_node_exporter_from_jenkins` (tcp/9100 from the Jenkins private IP `/32`) to `terraform/modules/security/main.tf`; `terraform apply` → `1 added, 0 changed, 0 destroyed`. Target flipped to UP on the next 15s scrape; `TargetDown` resolved. No console clicking, no host mutation.

### Prevention
- Every new scrape target needs a matching SG rule; the security module now carries both scrape rules side by side with descriptions so the pattern is obvious.
- The `TargetDown` alert (`up == 0` for 2m) is what should surface this in future, not the Targets page.

---

## Incident 5: Pipeline Push/Deploy stages never ran

**Date:** 2026-09-23

### Symptom
Every Jenkins build reported `SUCCESS`, but `Stage "Push" skipped due to when conditional` and `Stage "Deploy" skipped due to when conditional`. k3s was still running two 88-day-old pods from a hand-imported `crra:latest`; nothing had ever reached the cluster from the pipeline.

### Investigation
- `when { branch 'main' }` reads `BRANCH_NAME`, which is only set by Multibranch Pipeline jobs. This is a plain Pipeline job, so the condition is never true.
- The image was named `docker.io/crra` — no Docker Hub namespace. Docker silently tagged it `crra:<sha>`; a push would have been denied.
- Nothing carried the image from the Jenkins host's Docker to k3s (separate machine).

### Resolution
- `when { expression { (env.BRANCH_NAME ?: env.GIT_BRANCH ?: '').endsWith('main') } }` — works for both job types.
- Image namespaced under the Docker Hub credential's username: `docker.io/${DOCKER_CREDENTIALS_USR}/crra:<sha>`. Docker Hub auto-creates the repo on first push; k3s pulls it anonymously.
- Next build: Push uploaded layers, Deploy rolled out `docker.io/ppankh/crra:d1f739e82599` — the first pipeline-driven deploy.

### Prevention
- A pipeline that "passes" by skipping its last two stages is a false green. The Deploy stage should be followed by a verification step (Phase 7 adds one).

---

## Incident 6: Security-group allowlist for the VPN client went stale twice

**Date:** 2026-09-22 / 2026-09-23

### Symptom
`curl` to the k3s NodePort and SSH from the laptop timed out even though the client's address appeared to be allowlisted. `checkip.amazonaws.com` reported `15.248.3.5`, then `15.248.3.113`, then `15.248.2.149` across two days.

### Investigation
- The corporate HTTP proxy answers `checkip` on the client's behalf (`15.248.3.5`); raw TCP (SSH, NodePort) egresses from the VPN's NAT pool, a different address — found with `dig +short myip.opendns.com @resolver1.opendns.com`.
- Dogfish (`network=CORP, fwAggregate=true`) lists ~50 registered corp firewall aggregates, all `/25` or tighter. None contain any of the three observed addresses — the VPN NAT pool is generic AWS-owned space, not a registered corp egress.

### Resolution
`admin_cidrs.home` widened `/32` → `/24` → `/22` (`15.248.0.0/22`, the smallest block covering all observations), applied through `dev.tfvars` with 6 then 8 rules updated in place. Deliberately **not** `15.248.0.0/16`: AWS IT Security's "Overly scoped CIDR ranges" campaign flags allowlists that broad.

### Prevention
- Control-plane access (Ansible, SSH) now goes over SSM Session Manager — no client IP involved, so it cannot go stale. Only the three browser UIs (Jenkins, Prometheus, Grafana) still depend on the allowlist.
- The tfvars comment records the observations and the reasoning so the next widening is evidence-based, not a guess.
