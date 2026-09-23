# CRRA threat model

Scope: the two-host estate in account `066396400145` / `us-west-2` — the Jenkins host (CI, Prometheus, Grafana), the k3s host (the CRRA app), the Terraform state backend, the pipeline and the secrets that feed them. The app itself has no users or data of value; **the real assets are the CI host, which holds the ability to change everything, and the state backend, which describes everything.**

## How the ratings work

Likelihood and Impact are each scored 1–3. Risk = Likelihood × Impact (1–9).

| | 1 | 2 | 3 |
|---|---|---|---|
| **Likelihood** | needs a targeted attacker with prior access | opportunistic; scanners find this class of issue daily | already happened here, or will without action |
| **Impact** | one component degraded, recoverable from code | a host compromised or a service down; recoverable from code + state | control of the estate, or loss of the ability to rebuild it |

Risk 6–9 is mitigated before anything else ships. Risk 3–4 is mitigated when the cost is low, otherwise accepted with a reason. Risk 1–2 is accepted and recorded.

## Threats

| # | Threat | L | I | Risk | What is actually in place | Status |
|---|---|---|---|---|---|---|
| T1 | **Stolen long-lived AWS access key** from a Jenkins credential, a laptop or a leaked log | 2 | 3 | **6** | There is none to steal. Both hosts use instance profiles; the Jenkins CI role (`crra-jenkins-role`) is read-only for plan + state lock + scoped SSM/SSH. `terraform apply` is a human action with short-lived `ada` credentials. No AWS key exists in Jenkins Credentials. | Mitigated |
| T2 | **Jenkins controller compromised** (public UI on :8080, plugin CVEs) → attacker inherits the host's AWS identity | 2 | 3 | **6** | UI reachable only from the VPN NAT pool and the devdesk range (SG allowlist). The role it inherits cannot write to AWS — worst case is reading state and starting SSM sessions to the two `Project=crra` hosts. JNLP agent port 50000 is now closed (no agents exist). Unattended security upgrades on. | Mitigated; residual risk: SSM session to k3s host → kubectl. Accepted: that is what the pipeline legitimately needs. |
| T3 | **Secret in git or in Terraform state** (Grafana admin password, app token) | 3 | 2 | **6** | Secrets are SSM SecureStrings created out-of-band. Terraform reads them `with_decryption = false` — state holds KMS ciphertext and a postcondition refuses a plain `String`. Ansible resolves them at run time with the runner's own identity; `no_log` on the consuming tasks. `.dockerignore` limits the image context to `src/`, `setup.py`, `requirements.txt`. Historic: a placeholder vault password sat in git until Phase 6 — the vault file is now deleted. | Mitigated |
| T4 | **Two engineers apply to the same environment at once** → interleaved writes corrupt state | 3 | 3 | **9** | DynamoDB lock on every plan/apply; demonstrated live (S30). One state key per environment. S3 versioning keeps every prior state for `state push` recovery. `force-unlock` procedure in the runbook requires proving the holder is dead. | Mitigated |
| T5 | **State bucket deleted or emptied** → the estate can no longer be reasoned about or changed safely | 1 | 3 | **3** | `prevent_destroy` on the bucket; versioning; all four public-access blocks; TLS-only bucket policy; separate IAM for read (CI) vs write (humans). | Mitigated |
| T6 | **Internet-exposed ports on the hosts** (SSH brute force, k3s API, NodePort) | 3 | 2 | **6** | SSH :22 and every UI port are allowlisted to two CIDRs; k3s API :6443 and node_exporter :9100 accept only the Jenkins host's private IP; NodePort 30000 allowlisted. Ansible reaches hosts over SSM Session Manager, so :22 could be closed entirely (see T11). fail2ban and sshd hardening (no root, no password auth) from the hardening role. | Mitigated |
| T7 | **Allowlist goes stale** (VPN NAT pool moved three times in two days) → operator locked out, or widened to `/16` in a hurry | 3 | 1 | **3** | Control plane (Ansible/SSH) uses SSM — no client IP involved. Only browser UIs depend on the allowlist. Widening is a tfvars change with the evidence recorded in a comment; `/16` was rejected explicitly. | Accepted (residual: UI lockout, minutes to fix through code) |
| T8 | **Vulnerable base image or Python dependency** shipped to k3s | 2 | 2 | **4** | Trivy scans every image for HIGH/CRITICAL and archives the report; Bandit scans the source. **Neither currently fails the build** (`--exit-code 0`, `\|\| true`). Container runs as `appuser`, `python:3.11-slim` base, pinned requirements. | Partially mitigated. Accepted for now: gating on HIGH would block every build on Debian CVEs with no fix available; the report is reviewed, not enforced. Revisit with an allowlist of accepted CVEs. |
| T9 | **Unencrypted root volumes** on both hosts (tfsec HIGH ×2) | 1 | 2 | **2** | Encryption is launch-time only; fixing it replaces the hosts and loses Jenkins jobs and k3s state. Physical access to EBS storage in an AWS data centre is the only attack. Annotated `#tfsec:ignore` with the reason beside each resource. | Accepted |
| T10 | **Instance metadata credential theft** (SSRF from a container to `169.254.169.254`) | 2 | 3 | **6** | IMDSv2 required (`http_tokens = required`) on every instance, hop limit 2. | Mitigated |
| T11 | **Pipeline runs code from a branch other than `main`** and deploys it | 2 | 2 | **4** | Push, Deploy and Configuration Management stages gate on the branch name. Plain Pipeline job polls only `main`. | Mitigated; residual: anyone with write to `main` deploys. Accepted for a single-maintainer repo. |
| T12 | **Loss of the VPC's network audit trail** — no way to answer "who talked to what" after an incident | 2 | 1 | **2** | VPC flow logs to CloudWatch Logs, 30-day retention (added when tfsec flagged it). | Mitigated |

## Decisions worth explaining

**Why the CI role cannot `apply`.** Giving the pipeline write access would make T2 a full-estate compromise (Risk 9). Keeping apply human costs one manual step per infrastructure change; that trade is deliberate and stronger than the original brief's "store AWS credentials in Jenkins".

**Why T8 is accepted rather than gated.** A gate that fails every build is a gate people learn to bypass. The report is archived on every build and the base image is rebuilt on every push, so fixed CVEs disappear on their own. Enforcement waits until there is an allowlist mechanism for known-unfixable findings.

**Why T9 is accepted.** The fix is a host replacement. Ansible can rebuild the k3s host from nothing, but does not yet recreate Jenkins jobs and credentials, so replacing the Jenkins host today is a manual afternoon. The risk it mitigates requires physical access to AWS storage. Both hosts being unencrypted is recorded next to the resource, where the next person to touch it will see it.

**What would move the ratings.** A second maintainer raises T11 (branch protection and reviews become necessary). Any customer data in the app raises the Impact of T6 and T8 to 3. Either change should reopen this table.
