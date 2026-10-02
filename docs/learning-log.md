# Learning Log

## k3s (Lightweight Kubernetes)

**Date:** [To be filled during learning]

### What I Learned
- k3s is a lightweight, certified Kubernetes distribution designed for edge, IoT, and development
- Single binary installation, uses SQLite instead of etcd by default
- Ships with built-in ingress controller (Traefik) and service load balancer
- `kubectl` commands work identically to full Kubernetes

### Key Commands
```bash
curl -sfL https://get.k3s.io | sh -  # Install
sudo kubectl get nodes                 # Verify cluster
sudo kubectl get pods --all-namespaces # Check system pods
```

### Challenges Encountered
- Kubeconfig permissions required manual setup for non-root users
- Service ports required proper targeting in Service manifests

### Resources Used
- https://k3s.io/
- https://docs.k3s.io/

---

## Jenkins Declarative Pipelines

**Date:** [To be filled during learning]

### What I Learned
- Declarative pipelines use a structured `pipeline {}` block syntax
- Stages define logical groupings of steps
- `when` conditions control stage execution (e.g., only deploy on main branch)
- `post` blocks handle cleanup and notifications
- `credentials()` helper securely binds secrets to environment variables
- `pollSCM` triggers builds on repository changes

### Key Concepts
- `agent any` - run on any available executor
- `environment` block - define pipeline-wide variables
- `archiveArtifacts` - preserve build outputs
- `junit` - publish test results

### Challenges Encountered
- Jenkins credential management required understanding of credential types
- Pipeline syntax errors are only caught at runtime

### Resources Used
- https://www.jenkins.io/doc/book/pipeline/syntax/

---

## Trivy (Container Security Scanner)

**Date:** [To be filled during learning]

### What I Learned
- Trivy scans container images for known vulnerabilities (CVEs)
- Supports multiple severity levels: LOW, MEDIUM, HIGH, CRITICAL
- Can be integrated into CI/CD pipelines with exit codes for gating
- Scans OS packages and application dependencies

### Key Commands
```bash
trivy image <image-name>                    # Basic scan
trivy image --severity HIGH,CRITICAL <img>  # Filter by severity
trivy image --exit-code 1 <img>             # Fail on findings
trivy image --format json -o report.json    # JSON output
```

### Challenges Encountered
- Initial scans can be slow due to vulnerability database download
- False positives require investigation to determine if they apply

### Resources Used
- https://trivy.dev/

---

## TDD with pytest

**Date:** [To be filled during learning]

### What I Learned
- Test-Driven Development: write tests first, then implement until tests pass
- pytest discovers tests automatically by file/function naming conventions
- Fixtures provide reusable test setup (e.g., Flask test client)
- `pytest-cov` measures code coverage to identify untested paths
- Parametrize decorator reduces test duplication

### Key Patterns
```python
# Arrange-Act-Assert pattern
def test_example():
    data = {"key": "value"}      # Arrange
    result = process(data)        # Act
    assert result.status == "ok"  # Assert
```

### Challenges Encountered
- Mocking environment variables requires careful cleanup to avoid test pollution
- Coverage targets need to be realistic for meaningful enforcement

### Resources Used
- https://docs.pytest.org/

---

# Infrastructure module (Terraform, Ansible, Prometheus) — 22 Sep to 2 Oct 2026

Everything below was new to me in this module. Each entry records what I thought going in, what turned out to be true, and the command or file that proved it.

## Terraform `import` blocks

**Date:** 2026-09-22

### What I Learned
- Existing resources (the hand-built VPC, subnet, both EC2 instances) can be adopted without recreating them. Terraform ≥ 1.5 does this declaratively: an `import { to = …, id = … }` block makes the *plan* show what adopting the resource would change, before any state is written.
- The real work is not the import — it is writing resource blocks that match reality closely enough that the plan after import says `No changes`. Every attribute I had wrong showed up as an in-place update I did not intend.
- Import blocks are scaffolding: once applied and the plan is clean, they are deleted. The architecture doc records *that* the resources were imported; the code does not need to.

### Key Commands
```bash
terraform plan -generate-config-out=generated.tf   # draft resource blocks from the real thing
terraform plan                                     # must show only "import" actions, no changes
```

### Challenges Encountered
- Importing the instances brought their unencrypted root volumes into tfsec's view (Incident 7). Adopting a resource means adopting its findings.

---

## Dynamic inventory over SSM

**Date:** 2026-09-23

### What I Learned
- The Phase 0 failure (IPs changed on restart, everything that recorded an IP went stale) is an *inventory* problem. The `amazon.aws.aws_ec2` plugin queries EC2 by tag on every run, so there is no IP anywhere in the repo to go stale.
- Terraform's `Name` tag becomes the Ansible hostname and the `Role` tag becomes the group (`role_jenkins`, `role_k3s`). Adding a host is a Terraform change plus a tag; Ansible needs no edit.
- With `ansible_host` set to the instance ID and an SSH `ProxyCommand` of `aws ssm start-session … AWS-StartSSHSession`, SSH rides over the SSM API on 443. No inbound port 22, and it works from a devdesk that can only reach 80/443.

### Key Commands
```bash
ansible-inventory --graph                 # see what the tags produced
ansible all -m ping 2>/dev/null           # proves tags, SSM and credentials in one line
```

### Challenges Encountered
- The plugin needs credentials for `ec2:DescribeInstances` *and* SSM session permissions; a half-granted role fails with a confusing SSH error rather than an AWS one.

---

## `moved` blocks (instead of `terraform state mv`)

**Date:** 2026-09-23

### What I Learned
- Refactoring flat resources into `network` / `compute` / `security` modules changes every resource address. Without telling Terraform, the plan is "destroy 14, create 14" — of live hosts.
- `terraform state mv` fixes that imperatively, one address at a time, and leaves no trace in git. A `moved { from = aws_vpc.main  to = module.network.aws_vpc.main }` block does the same thing *in code*: the plan reads `aws_vpc.main has moved to module.network.aws_vpc.main`, it is reviewed like any other change, and it applies the same way in every environment.
- Proof of a safe refactor is a plan with zero `+`/`-`/`~` — only moves. I did not apply until I had that.

### Challenges Encountered
- IAM role and policy names are account-global, so a second environment in the same account collides on `crra-jenkins-role`. Fixed with a `name_prefix` variable; making it a no-op for dev (`crra-`) was the part that needed care.

---

## tfsec

**Date:** 2026-09-23

### What I Learned
- A static scanner on Terraform catches things a plan never will: an IAM action on `*`, a subnet that hands out public IPs, a security-group rule to `0.0.0.0/0`. It runs in seconds, with no credentials, so it belongs *before* the plan stage.
- It fails the build on its own author's code. The first run found 7 issues in infrastructure that had been working for a week — three of them in the IAM policy I had written that same day.
- Not every finding is a fix. `#tfsec:ignore:<rule>` is the right answer when the risk is understood, **provided the reason is written beside the resource**. An ignore with no reason is just a disabled check.

### Key Commands
```bash
tfsec terraform/environments/dev --tfvars-file dev.tfvars   # plain output; the pipeline uses --format json
```

### Challenges Encountered
- tfsec 1.28 predates Terraform `check {}` blocks, so an assertion that SSM parameters are `SecureString` had to be a `lifecycle { postcondition }` on the data source instead.

---

## PromQL

**Date:** 2026-09-23

### What I Learned
- Counters only go up; the useful number is their *rate*. `rate(crra_http_requests_total[5m])` turns a monotonic count into requests per second over a 5-minute window; `sum by (status)` groups it.
- A ratio of two rates is a percentage that does not depend on traffic volume: `sum(rate(…{status=~"5.."}[5m])) / sum(rate(…[5m])) > 0.05` is "more than 5 % errors", whether the service does 1 or 1000 req/s.
- Histograms store buckets; `histogram_quantile(0.95, sum by (le, endpoint) (rate(…_bucket[5m])))` gives p95 latency per endpoint. `le` must survive the `sum by` or the quantile is meaningless.
- An alert has a `for:` duration so a single bad scrape does not fire it. `TargetDown` waits 2 minutes, `CrraHighErrorRate` 5.

### Challenges Encountered
- `up == 0` with a `dial tcp …:9100: i/o timeout` was not Prometheus or node_exporter at all; it was a missing security-group rule (Incident 4). The metric told me *where*, not *why*.

---

## Least privilege in CI

**Date:** 2026-09-23 and 2026-10-02

### What I Learned
- A keyless instance role for Jenkins means no AWS access key exists anywhere in Jenkins. The cost is that every API call the pipeline makes must be enumerated — and `terraform plan` makes calls I never typed (`ec2:DescribeInstanceAttribute`, `logs:DescribeLogGroups`, `kms:ListAliases`).
- Admin credentials on my devdesk hid every gap. The pipeline's narrow role found them on the first real run, twice (Incidents 7 and 9). That is the role doing its job, not a reason to widen it.
- The honest fix is `TF_LOG=debug` to see the exact denied call, then exactly that action, on the narrowest ARN the action supports.

---

## What I would do differently

- **Scan before building.** tfsec and ansible-lint went in at Phase 7, after a week of infrastructure. Had they been in the first commit, Incident 7 would have been seven small fixes over seven days instead of one red build.
- **Never `git add -A`.** It committed my editor's `.kiro/` settings folder. Name the files.
- **Never paste a placeholder.** `--value '<vault_grafana_admin_password>'` stored the literal placeholder as the secret. Generate secrets in place (`$(openssl rand -base64 24)`) so there is nothing to copy wrongly.
- **Open the PR first.** The module refactor landed on `main` directly because I was the only contributor. The `moved`-block plan was exactly the kind of change a second pair of eyes should have read before apply; the close-out PR in Phase 11 is the habit I should have started with.
- **One environment is not proof of modules.** Staging only exposed the account-global name collision once it existed. Build the second environment at the same time as the first module.
