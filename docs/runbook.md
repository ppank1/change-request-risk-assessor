# CRRA Infrastructure Runbook

How the CRRA infrastructure is operated. For application-level operations (scaling pods, rollbacks, reading logs) see [operations-runbook.md](operations-runbook.md).

## Policy: no manual mutation

**Nothing on a CRRA host or in the CRRA AWS account is changed by hand.**

| Kind of change | Goes through | Never through |
|---|---|---|
| AWS resources (instances, security groups, IPs, IAM, state backend) | `terraform plan` → review → `terraform apply` in `terraform/environments/<env>` | AWS console, `aws ec2 modify-*`, `aws ec2 authorize-*` |
| Software and configuration inside a host | `ansible-playbook` against the dynamic inventory | SSH followed by `apt`, `vim`, `systemctl edit` |
| Base host image or bootstrap | Change `user_data` / AMI in Terraform, then **replace** the instance | Patching the running instance |
| Application version | Jenkins pipeline: SHA-tagged image → `kubectl apply` | `kubectl set image` by hand, `docker pull :latest` on the host |

The reason is the incident on 2026-09-22: both instances were restarted, their public IPs changed, and the Jenkins root URL — set by hand in the UI — silently went stale. Nothing recorded that the value existed, so nothing could have re-asserted it. A hand-made change is invisible to every tool that manages the system. If it is not in Terraform, Ansible or the pipeline, it does not exist and will be lost at the next rebuild.

SSH is for **reading**: logs, `systemctl status`, `kubectl get`. If a read reveals a fix is needed, the fix is a code change.

**Break-glass.** If production is down and a manual change is the fastest recovery: make it, then within the same working day (a) record it in `docs/troubleshooting-log.md` and (b) land the equivalent change in Terraform/Ansible so the next `plan` / `playbook` run is clean. The manual change is a loan, not a fix.

## Deploying

There is one way to deploy: push to `main`. The Jenkins job `crra-pipeline` runs Lint → Test → Security Scan → Terraform Validate → IaC Security Scan → Ansible Lint → Terraform Plan → Docker Build → Trivy Scan → Push → Deploy → Configuration Management. Nothing after the Plan stage runs unless every gate before it passed, and Push/Deploy run only on `main`.

- **Application change** — merge to `main`. Deploy pins the image to `docker.io/ppankh/crra:<git-sha>`, runs `kubectl rollout status`, checks `/health` through the Service and asserts every running pod is on that SHA. The build is green only when both the rollout and the Ansible run (`changed=0`) finished.
- **Infrastructure change** — Terraform is *planned* by the pipeline, never applied. Open a PR, read `reports/terraform-plan.txt` archived on the PR's build, merge, then an operator applies from a devdesk: `terraform apply -var-file=<env>.tfvars` in `terraform/environments/<env>`. The next build's plan must then be `No changes`.
- **Host configuration** — Ansible roles are applied by the Configuration Management stage on every build, with the Jenkins instance role. An operator can also run `ansible-playbook playbooks/site.yml` with `ada` credentials; the result must be the same.

Build watch without the UI (SSM only, no VPN): `ansible crra-jenkins-001 -m shell -a 'tail -5 $(ls -d /var/lib/jenkins/jobs/crra-pipeline/builds/[0-9]* | sort -V | tail -1)/log'`.

## Rolling back

| What went wrong | Roll back with | Notes |
|---|---|---|
| Bad application release | `kubectl rollout undo deployment/crra -n crra-dev` **then** `git revert` the commit and push | `undo` restores the previous ReplicaSet in seconds (Incident 8). The revert is still required: the next push would otherwise redeploy the bad SHA. |
| Bad image tag / pull failure | Same as above | With `maxUnavailable: 0` the old pods keep serving while the new one sits in `ImagePullBackOff` — users are not affected; fix at leisure. |
| Bad Terraform apply | `git revert` the commit, `terraform plan`, read it, `terraform apply` | State is versioned in S3; a plan from the reverted code is the rollback. Never edit state by hand. For an instance that must go back to a previous AMI/`user_data`, that is a replacement (below). |
| Bad Ansible change | `git revert`, re-run `site.yml` | Roles are idempotent; the previous template is re-rendered and the service restarted by its handler. |
| Bad secret value | `aws ssm put-parameter --overwrite` with the previous version's value (`get-parameter-history`), re-run `site.yml` | Grafana only reads its password at first start — rotate the live one with `grafana-cli admin reset-admin-password` (Secrets, below). |

## Responding to alerts

Prometheus evaluates `alerts.yml` (rendered by the `monitoring` role); there is no Alertmanager, so an alert is visible at `http://<jenkins-eip>:9090/alerts` and on the Grafana overview, not paged. Scrapes come from the Jenkins host's private IP only (the 9100 rule in `modules/security` allows exactly that /32), so a `TargetDown` is never caused by anything outside the VPC.

| Alert | Fires when | First look | Likely causes and fix |
|---|---|---|---|
| `TargetDown` (critical) | `up == 0` for 2 min on any scrape job (`prometheus`, `node`, `crra-app`) | `/targets` in Prometheus: which job, which instance, the scrape error text | **`node` on a host** — instance stopped or node_exporter dead: `aws ec2 describe-instances`, then `ansible <host> -m shell -a 'systemctl status node_exporter'`; fix is `site.yml`, not `systemctl start`. **`i/o timeout` to port 9100** — security-group rule missing (Incident 4): confirm in `modules/security`, `terraform plan`. **`crra-app`** — pods not Ready or NodePort 30000 not answering: `kubectl get pods -n crra-dev`, `kubectl describe pod`, then see Rolling back. |
| `CrraHighErrorRate` (warning) | 5xx > 5 % of requests over 5 min, for 5 min | Grafana *HTTP by status* panel; `kubectl logs -n crra-dev deploy/crra --since=10m` | Usually the last deploy — compare the firing time with the latest build; `rollout undo` first, read logs second. A single bad client sending malformed requests produces 4xx, not 5xx, and does not fire this. If the rate is real and not release-related, scale: `kubectl scale deployment/crra -n crra-dev --replicas=3`, then land the number in `k8s/deployment.yaml`. |

After any alert: one line in `docs/troubleshooting-log.md` — what fired, what it was, what changed in code so it cannot recur.

## Rebuilding a host (immutable replacement)

Hosts are replaced, not repaired. The instance is destroyed and a new one is created from the same code; `user_data` brings it to the baseline, Ansible layers on the role.

```bash
cd terraform/environments/dev
terraform plan -var-file=dev.tfvars -replace=module.compute.aws_instance.<host>
terraform apply -var-file=dev.tfvars -replace=module.compute.aws_instance.<host>
```

What survives a replacement:
- **Elastic IP** — re-associated to the new instance, so external URLs and allowlists are unchanged.
- **Private IP** — pinned in `dev.tfvars`, so intra-VPC rules (k3s API from Jenkins) still hold.
- **Key pair, security groups, subnet** — separate resources; untouched.

What does not survive: anything on the root volume that was not put there by `user_data` or Ansible. That is the point.

Verify after replacement, no SSH needed:

```bash
curl -s http://<elastic-ip>:8000/ | jq .      # bootstrap health marker: host, role, bootstrapped_at, instance_id
aws ec2 describe-instances --instance-ids <new-id> --query 'Reservations[].Instances[].State.Name'
```

## Elastic IPs

Both hosts have an EIP managed in `modules/compute`. Stop/start no longer changes public addresses. The Jenkins root URL is set once to the EIP (via Ansible) and needs no further updating.

## Terraform state

- Backend: S3 `crra-tfstate-<account>` (versioned, encrypted, TLS-only) with DynamoDB lock `crra-tfstate-lock`, created by `terraform/bootstrap`.
- One bucket, one lock table, **one key per environment**: `dev/terraform.tfstate`, `staging/terraform.tfstate`. Each environment root (`terraform/environments/<env>/`) has its own `backend.tf` naming its key and its own `<env>.tfvars`. Two engineers in different environments never contend; two in the same environment are serialised by the lock.
- Recovering a bad state write: S3 versioning keeps every prior state — download the previous version and `terraform state push`.

### Working in a team: what the lock does

Every `plan` (unless `-lock=false`), `apply`, `import` and `state` command writes a lock item to DynamoDB before touching state. A second operator on the same environment sees:

```
Error: Error acquiring the state lock
Lock Info:
  ID:        <uuid>
  Path:      crra-tfstate-<account>/dev/terraform.tfstate
  Operation: OperationTypeApply
  Who:       <user>@<host>
  Created:   <timestamp>
```

That is the system working. Wait for the holder to finish (`Who` tells you who to ask), then retry. Read-only checks that must not wait can use `terraform plan -lock=false` — never `apply -lock=false`. The Jenkins pipeline's plan stage takes the lock like any operator, so a build and an engineer's apply cannot interleave.

### Stuck lock

A lock survives its holder only when the process died mid-run (laptop closed, SSH dropped, CI job killed). Before touching it:

1. Read the lock: `Who` and `Created`. If it is minutes old, ask the person — they may still be running.
2. Confirm the process is gone: on the `Who` host, `pgrep -af terraform`; for Jenkins, check the build is not in progress.
3. Only then: `terraform force-unlock <LOCK_ID>` from the same environment directory. It removes the DynamoDB item and nothing else.

`force-unlock` is safe when the holder is dead. It is **never** safe while an apply is running: the next operator's writes would interleave with the live run and the state file can end up describing neither. If in doubt, wait — a stale lock costs minutes; a corrupted state costs an afternoon with S3 versions.

## Secrets

Runtime secrets live in **SSM Parameter Store as SecureString**, under `/crra/<env>/`. Nothing secret is in git, in Terraform state (Terraform reads them without decryption), in an Ansible vault file, or in a Jenkins credential. The only Jenkins credentials are the Docker Hub login and the SSH key.

| Parameter | Consumer |
|---|---|
| `/crra/dev/grafana/admin_password` | `monitoring` role → `grafana.ini` (first start only; rotate with `grafana-cli admin reset-admin-password`) |
| `/crra/dev/app/api_token` | `common` role → `/etc/crra/environment` |

**Create or rotate** (operator, admin credentials):

```bash
aws ssm put-parameter --region us-west-2 --type SecureString --overwrite \
  --name /crra/dev/grafana/admin_password --value "$(openssl rand -base64 24)"
```

Then `ansible-playbook playbooks/site.yml` to push the new value to the hosts. `terraform plan` for the environment must show `No changes` afterwards — Terraform tracks the parameter's ARN and type, never its value.

**Who can read them.** Ansible resolves each secret with `lookup('amazon.aws.aws_ssm', ...)` using whatever identity runs the playbook: an operator's `ada` credentials from a devdesk, or the Jenkins host's instance role in the pipeline. The CI role is granted `ssm:GetParameter` on exactly these ARNs and `kms:Decrypt` on the SSM key only via SSM (`kms:ViaService`) — see `terraform/environments/dev/secrets.tf` and the `ReadRuntimeSecrets` statement in the security module. It cannot `PutParameter`.

**Adding a secret:** add it to `local.secret_parameters` in `secrets.tf` (Terraform then fails the plan until the parameter exists and is a SecureString), create it with `put-parameter`, reference it in `group_vars/all/vars.yml`, mark the consuming task `no_log: true`.

## Routine checks

| Check | Command | Expect |
|---|---|---|
| Drift | `terraform plan -var-file=dev.tfvars` | `No changes.` — anything else is drift or an unlanded change |
| Hosts up | `aws ec2 describe-instances --filters Name=tag:Project,Values=crra --query 'Reservations[].Instances[].[Tags[?Key==\`Name\`]\|[0].Value,State.Name]' --output table` | all `running` |
| Config drift inside hosts | `ansible-playbook playbooks/site.yml --check` | `changed=0` |

## Known failure modes

Each of these has happened once. The symptom is what you will see first; the number is the entry in [troubleshooting-log.md](troubleshooting-log.md).

| Symptom | Cause | What prevents it now | # |
|---|---|---|---|
| Jenkins URL / dashboards unreachable after a stop-start; Jenkins root URL wrong | Public IPs changed; a hand-set value had no owner | Elastic IPs in Terraform; root URL set by Ansible; *no manual mutation* policy | (Policy, above) |
| `permission denied … /var/run/docker.sock` in a build | Jenkins user not in the `docker` group | `jenkins` role manages group membership | 1 |
| Pod `CrashLoopBackOff` right after deploy | Readiness probe fired before the app was listening | `initialDelaySeconds` raised; `/health` checked through the Service before the build goes green | 2 |
| Pod `ImagePullBackOff`, rollout never completes, users unaffected | Image tag does not exist | `maxUnavailable: 0`; image tag is the git SHA, never typed by hand | 3, 8 |
| Prometheus `TargetDown`, `dial tcp …:9100: i/o timeout` | No security-group rule for node_exporter | Rule in `modules/security` from the Jenkins /32; tfsec gate | 4 |
| Every build green, nothing ever deployed | `when { branch }` gate never matched a plain Pipeline job | Gate checks `GIT_BRANCH` in both forms; Deploy asserts pods are on the new SHA | 5 |
| Operator locked out of 8080/3000/9090 | VPN egress IP changed; allowlist was a /32 | Allowlist is the corporate egress /22 plus the devdesk range, in `dev.tfvars` | 6 |
| Build fails at Terraform Plan with `AccessDenied` | CI instance role lacks a read the plan now makes (new data source, new resource type) | Enumerate the call with `TF_LOG=debug`, add exactly that action to `modules/security` — never a wildcard | 7, 9 |
| Build fails at IaC Security Scan | New Terraform introduced a tfsec finding | Fix or annotate `#tfsec:ignore:<rule>` **with the reason** beside the resource | 7 |
| Deploy succeeds, health check exits 137 | Health probe hit a terminating old pod | Probe goes through the Service, then asserts every Running pod is on the new image | 7 |
| `Error acquiring the state lock` | Another operator or a build holds the lock | Expected — see *Working in a team*; `force-unlock` only for a dead holder | — |
| Ansible run `changed>0` when nothing was meant to change | A value drifted outside code (secret, hand edit) | Treat as drift: find the source, land it in code, re-run until `changed=0` | — |

## Adding a new host

1. Add the instance and its EIP to `modules/compute`, its security group to `modules/security`.
2. `terraform plan` — review that only the new resources are added.
3. `terraform apply`.
4. Tag it `Role=<role>`; the Ansible dynamic inventory picks it up with no inventory edit.
5. `ansible-playbook playbooks/site.yml --limit <role>`.
