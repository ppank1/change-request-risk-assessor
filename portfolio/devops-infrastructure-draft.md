# DevOps Infrastructure

## Introduction

As a DevOps Apprentice at Amazon Web Services (AWS), I continued the Change Request Risk Assessor (CRRA) project from the previous module, which delivered a Python service, a Jenkins pipeline and a k3s deployment on two EC2 instances I had built by hand. This phase turned those hosts into infrastructure that is defined, configured, monitored and secured by code.

The trigger was a failure. When the instances were restarted between modules, both received new public IPs and the Jenkins root URL, typed in by hand, was wrong. The pipeline survived only because its Jenkins-to-k3s path used the private IP. Anything configured by hand drifts.

By the end of this phase, all 21 AWS resources were under Terraform with remote, locked state; both hosts were configured by idempotent Ansible roles over AWS Systems Manager (SSM) rather than SSH; Prometheus and Grafana monitored the hosts and the application; the pipeline grew from eight to thirteen stages; and a staging environment came from the same modules as dev. Tests grew from 15 at 87% coverage to 20 at 89%.

## Project Context and Objectives

The CRRA scores change requests against five risk dimensions and returns LOW, MEDIUM, HIGH or CRITICAL. The business driver for this phase was operability: a system that assesses the risk of other people's changes must itself be rebuildable, auditable and observable.

The objectives were to:

- Bring the hand-built AWS infrastructure under Terraform without destroying it, and prove the code matches reality.
- Replace in-place host changes with immutable patterns: Elastic IPs, replacement over mutation, SHA-tagged images.
- Configure both hosts with idempotent Ansible roles that need no stored IPs or open SSH ports.
- Add host and application monitoring with a live alert.
- Extend the pipeline to validate, scan and plan the infrastructure code on every commit.
- Separate dev and staging, demonstrate safe shared-state working, and write a threat model that drives decisions.

## Architecture Overview

The target state keeps the two-instance footprint (the budget) and changes how it is managed. Terraform owns every AWS resource, with state in a versioned, encrypted S3 bucket and a DynamoDB lock table. Ansible owns everything inside the instances through six roles, selecting hosts by tag and connecting over SSM on port 443. Prometheus and Grafana run on the Jenkins host; `node_exporter` runs on both; the application exposes `/metrics`.

*(Screenshot showing the target-state diagram: Terraform with S3/DynamoDB remote state, both instances on Elastic IPs, Ansible via dynamic inventory, Prometheus scrape paths, and the Jenkins-to-k3s deploy path over the private IP.)*

From commit to running service: a push to `main` triggers Jenkins; the application is linted, tested and scanned; the Terraform and Ansible code is validated, scanned and planned; the image is built, scanned and pushed under its commit SHA; `kubectl` performs a rolling update over the private IP and asserts every pod is on that SHA; finally the Ansible site playbook runs against both hosts and must report `changed=0`.

I modelled this with a colleague before writing code. My first proposal, an Ansible task to rewrite the Jenkins URL after each restart, was rejected as fixing the symptom. The design that emerged uses private IPs internally and Elastic IPs externally.

*(Screenshot showing a redacted Slack thread where a colleague rejected my "rewrite the IP with Ansible" option as fixing a symptom, leading to the private-IP-internal / Elastic-IP-external pattern and the import-then-immutable approach.)*

## Infrastructure as Code

#### State backend

I built the state backend first, as its own configuration with local state, because it creates the bucket everything else depends on: versioned, AES256-encrypted, all public access blocked, TLS-only. I chose DynamoDB locking because two engineers running `apply` against the same state can corrupt it, and the lock makes that impossible rather than merely unlikely.

*(Screenshot showing the state-backend plan: 6 resources to add, with all four public-access blocks `true`, `sse_algorithm = "AES256"` and versioning `Enabled` visible, and the plan saved to `bootstrap.tfplan` before anything is created.)*

#### Import, not rebuild

I imported the live infrastructure rather than recreating it, because destroying the hosts would have lost the Jenkins jobs and k3s state. Declarative `import` blocks let me write the configuration for all 21 resources and read the plan before anything happened.

*(Screenshot showing 21 hand-built resources, VPC, subnet, routing, both security groups and their 12 rules, key pair and both instances, imported via declarative `import` blocks: "21 imported, 0 added, 0 changed, 0 destroyed".)*

The proof is the plan that follows. With the import blocks removed, `terraform plan` returned "No changes. Your infrastructure matches the configuration." The HCL describes every live resource exactly, and from then on any drift is a plan diff.

*(Screenshot showing the post-import `terraform plan` returning "No changes. Your infrastructure matches the configuration." The codified definitions describe all 21 live resources exactly.)*

#### Modularisation as a behaviour-preserving refactor

A flat root of 21 resources is correct but not reusable, so I refactored it into `network`, `security` and `compute` modules with a per-environment root. The risk is that Terraform treats a resource at a new address as new and destroys the old one. I used `moved` blocks rather than `terraform state mv` because they are declarative, reviewable in the diff and applied by the same plan everyone reads. All 21 resources relocated with "0 to add, 0 to change, 0 to destroy", and the plan after apply was again "No changes".

*(Screenshot showing the refactor was behaviour-preserving: all 21 resources relocated from flat addresses into the `network`/`security`/`compute` modules via `moved` blocks with "0 to add, 0 to change, 0 to destroy", and the follow-up plan returning "No changes".)*

Once dev had applied them, the `moved` blocks were dead code; removing them was the change I later put through peer review.

## Immutable Infrastructure

The restart incident was a mutation problem: a host patched by hand held state nobody could reproduce. I addressed it at three levels.

Both hosts received Elastic IPs, so stop/start changes no address and the Jenkins URL is a Terraform output. The EIPs carry `prevent_destroy`, because a released address cannot be recovered.

Hosts are replaced, not edited. To prove it I built a disposable test instance configured entirely by `user_data` and rebuilt it with `terraform apply -replace`: destroyed in 31 seconds, recreated from the same code in 14, nothing else touched, and the replacement answered its own health check unaided.

*(Screenshot showing `terraform apply -replace` destroying `crra-test-001` (31s) and creating its successor from the same code (14s): "1 added, 0 changed, 1 destroyed", nothing else touched.)*

Images are tagged by commit SHA. The previous module's `:latest` made two questions unanswerable: what is running, and what do I roll back to. The deploy stage now asserts every running pod is on the SHA it just built, and the runbook states the rule: a change that cannot be expressed in code is not made.

## Configuration Management

Six Ansible roles (`common`, `docker`, `jenkins`, `k3s`, `monitoring`, `hardening`) own everything inside the instances.

#### Dynamic inventory over SSM

The inventory holds no IPs and no SSH keys. The `amazon.aws.aws_ec2` plugin selects instances tagged `Project=crra`, and the connection goes over SSM Session Manager, outbound 443 from the host. I chose this over a static `hosts.ini` because a static inventory holds IPs, and IPs were exactly what had changed. It also means no inbound port 22 and a control plane that a stale allowlist cannot lock out. Getting the SSM connection plugin working was the steepest learning of the module.

*(Screenshot showing the `aws_ec2` dynamic inventory resolving both hosts by tag into `role_jenkins` / `role_k3s`, and ping returning pong from each over SSM. No IP is stored anywhere and no inbound port 22 is needed.)*

#### Idempotency as evidence

The first `site.yml` run applied 15 changes per host and exposed real drift on the hand-built Jenkins host: a conflicting apt `Signed-By` path from months earlier. I corrected the role to own the sources file rather than patching the host. The immediate second run reported `changed=0` on both hosts, which is what makes the playbook safe to run from the pipeline on every commit.

*(Screenshot showing the immediate re-run of site.yml: PLAY RECAP `changed=0 failed=0` on both hosts. The roles are idempotent, so repeated runs converge to the declared state and act as drift prevention rather than change.)*

#### Secrets and cost

Secrets began in Ansible Vault, consumed by `no_log` tasks writing a root-only `0600` file; the security phase moved them out of the repository (below).

On effort against cost: the roles took about two days to write and debug. Configuring both hosts now takes under four minutes on every build, where the manual equivalent took most of a day and could not be verified. The automation paid for itself on the second environment.

## Monitoring and Observability

Prometheus and Grafana run on the Jenkins host, the larger of the two; `node_exporter` covers the hosts, but the more important source is the application.

I added a `/metrics` endpoint to the Flask service with `prometheus_client`, test-first, with five new tests: request count by method, route and status, request duration, and assessments by risk level. Labels use the matched route, not the raw path, so random URLs cannot create unbounded cardinality. The endpoint sits behind an `ENABLE_METRICS` toggle, default off, enabled by the ConfigMap, so the code merged to `main` before the monitoring stack existed.

*(Screenshot showing the Prometheus Targets page with all three jobs UP: `prometheus`, `node` on both hosts, and `crra-app` scraping `/metrics` through the NodePort.)*

The first Prometheus run showed the `crra-k3s-001` node target DOWN with `dial tcp ...:9100: i/o timeout`. I ruled out one layer per test: the exporter was listening on the host; a `curl` from the Jenkins host timed out rather than being refused, pointing at a firewall; and `describe-security-group-rules` showed the k3s group allowed the Jenkins host on 6443 and 30000 but not 9100. One ingress rule in the `security` module, applied through Terraform, and the target was UP on the next scrape.

*(Screenshot showing the `node` target DOWN with an `i/o timeout` to port 9100, the diagnosis isolating the missing security-group rule, and the target UP after a single Terraform-applied rule.)*

Two alert rules are live: `TargetDown` (`up == 0` for two minutes) and `CrraHighErrorRate` (5xx above 5% for five minutes). `TargetDown` fired during that incident and resolved with the fix, so the alert path is proven.

*(Screenshot showing the Grafana dashboard with live CRRA request rate, latency and assessments by risk level, and the Prometheus alerts page with `TargetDown` and `CrraHighErrorRate` loaded.)*

## Pipeline Extension

The pipeline grew from eight to thirteen stages. Before anything is built: Terraform Validate on both roots, tfsec, Ansible Lint, and a Terraform Plan archived as an artefact so a reviewer can read what the commit would do. After deploy, Configuration Management runs `site.yml` against both hosts.

Each stage guards one failure. Validate catches HCL that will not parse; tfsec catches insecure resources before they exist; Ansible Lint catches non-idempotent tasks. The plan is a preview, not a change: the pipeline deliberately cannot `apply`, because write access would turn a Jenkins compromise into control of the estate. The configuration stage must report `changed=0`, or something changed outside code.

*(Screenshot showing the full 13-stage pipeline green in one build: the plan reports "No changes" using the Jenkins host's own instance role. Live infrastructure matches the code, and no AWS access key exists anywhere in Jenkins.)*

*(Screenshot showing the pipeline's rolling update: the image pinned to the commit SHA, `rollout status` reporting new replicas coming up while old ones drain, then /health verified through the Service and both pods confirmed on the new tag.)*

## Security and Threat Management

The threat model (`docs/threat-model.md`) scores twelve threats on likelihood and impact from 1 to 3, risk as the product: 6 and above mitigated before anything ships, 3 to 4 mitigated when cheap or accepted with a reason, 1 to 2 accepted and recorded. Its framing decision: the application holds no data of value, so the real assets are the CI host, which can change everything, and the state backend, which describes everything.

That framing drove the choices. Two engineers applying to the same state (Risk 9) is why locking was built first. A stolen long-lived AWS key (Risk 6) is mitigated by there being no key: both hosts use instance profiles and `apply` stays human, with short-lived credentials. A compromised Jenkins controller (Risk 6) inherits a role that cannot write to AWS; I also closed the JNLP agent port, open to the internet since the previous module with nothing using it.

Secrets in git or state (Risk 6) moved to SSM Parameter Store as SecureStrings. Terraform reads them with `with_decryption = false`, so state holds only ciphertext, and a postcondition fails the plan if either becomes a plain `String`. The CI role can read exactly those two ARNs.

*(Screenshot showing the two runtime secrets as SSM SecureStrings, the Terraform data source that reads them without decryption, and the CI role's policy granting read on exactly those ARNs.)*

Some risks were accepted deliberately. Trivy and Bandit report but do not fail the build: gating on HIGH would block every build on Debian CVEs with no fix, and a gate people learn to bypass is worse than a report people read. The live hosts' root volumes are unencrypted; the fix is a replacement that loses Jenkins state, against an attack needing physical access to AWS storage.

*(Screenshot showing the IaC Security Scan stage before and after: tfsec finds 7 issues and every downstream stage is skipped; after the fixes, 41 passed, 6 ignored with a written reason each, no problems.)*

## Multi-Environment and Team Working

A staging root was added from the same three modules with its own tfvars (different VPC CIDR, smaller instances, different names) and its own state key. Creating it exposed a defect one environment could not: IAM role names are account-global, so the modules needed a `name_prefix` before two environments could share an account. That refactor planned as a no-op for dev.

*(Screenshot showing dev and staging as sibling roots sharing the same three modules: each has its own state key in the one bucket and its own tfvars with different VPC, sizes and names, same code.)*

I then demonstrated the lock. One terminal held an `apply` at its confirmation prompt; a second ran `plan` on the same state and was refused with `ConditionalCheckFailedException` and a lock record naming the operation, holder and time. The runbook allows `force-unlock` only after proving the holder's process is dead, because unlocking under a live apply recreates the corruption the lock exists to prevent.

*(Screenshot showing two engineers on the same environment: terminal A holds the DynamoDB state lock mid-apply, terminal B is refused with the lock ID, path, operation and holder.)*

Internal standards shaped the allowlists: when the VPN egress address moved three times in two days I widened the admin CIDR to a `/22`, the smallest covering block, and rejected `/16` because the internal "overly scoped CIDR" campaign flags it. Externally, the `amazon.aws` and tfsec issue trackers resolved the SSM connection plugin and tfsec's lack of `check`-block support.

## Challenges and Resolutions

#### The security gate failed on its author's code

Symptom: the first build after adding tfsec failed with 7 findings. Hypothesis: imported resources carried insecure defaults, and my new IAM policy had wildcards. Test: tfsec locally per root, grouped by cause. Root cause: imported-estate defaults (unencrypted volumes, public-IP subnet, no flow log) and three genuine wildcards in the CI policy written that week. Fix: four fixed in code, six accepted with a reason beside each resource. Prevention: accepted risks live in the same diff as the resource.

#### Least privilege broke the pipeline twice

Symptom: Terraform Plan in Jenkins failed with `AccessDenied: logs:DescribeLogGroups`, and later with `kms:ListAliases`. Hypothesis: the CI role lacked read actions for resources added since it was written. Test: the plan locally with `TF_LOG=debug`, listing every API call. Root cause: the flow-log group from the tfsec fix, then a `data "aws_kms_alias"` lookup I added; admin credentials on my desk had masked both. Fix: exactly the missing read actions, never `logs:*` or `kms:*`. Prevention: the pipeline's own plan, not a local admin plan, is the test.

#### A rolling update that killed its own health check

Symptom: Deploy exited 137 after `deployment "crra" successfully rolled out`. Hypothesis: something was killed after the rollout. Test: read `deploy.sh`; it checked health with `kubectl exec` into `.items[0]`. Root cause: right after a rolling update, pod zero is often the old pod still terminating, so the exec was SIGKILLed; Deploy had never run from the pipeline before. Fix: health checked through the Service, the path real clients use, plus an assertion that every running pod is on the new image. Prevention: that assertion fails the build on any bad tag.

## Collaboration and Knowledge Sharing

The module refactor went to `main` directly, as I was the only contributor. For its close-out, removing the dead `moved` blocks and finishing the runbook, I opened a pull request with three explicit review questions. The reviewer challenged whether deleting `moved.tf` could cause a destroy-and-recreate, asked how the runbook distinguishes a dead Prometheus from a dead target at 2am, and noted that reverting a destroyed resource recreates it with a new ID. Each produced a fixup commit: plan evidence in the description, a "rule out Prometheus first" step and an ID note in the runbook, and `prevent_destroy` on the EIPs.

*(Screenshot showing the module-refactor close-out going through peer review: the reviewer challenged the moved-block removal, the plan evidence answered it, and the change was approved before merge.)*

The runbook covers deploying, rolling back each kind of change, responding to each alert, secret rotation, lock recovery and eleven known failure modes mapped to the troubleshooting log. I also walked a colleague through why the inventory reaches hosts over SSM rather than SSH.

*(Screenshot showing a redacted thread where I walked a colleague through why the Ansible inventory reaches hosts over SSM on port 443 instead of SSH, and why that still works without VPN.)*

## Skills and Behaviours Demonstrated

| KSB | Evidence in this phase |
|---|---|
| S1 | Wrote the runbook, threat model and architecture document for engineers, and a PR description with explicit review questions that a reviewer with no prior context could answer. |
| S2 | Worked within AWS internal tagging and the "overly scoped CIDR" security standard (rejecting a `/16` allowlist), while resolving the SSM connection plugin and tfsec `check`-block limitation through the `amazon.aws` and tfsec open-source communities. |
| S4 | Shared the runbook, troubleshooting log and six role READMEs; walked a colleague through the SSM-over-443 inventory pattern, which they adopted. |
| S5 | Elastic IPs with `prevent_destroy`, a host rebuilt with `terraform apply -replace` in 45 seconds from code alone, SHA-tagged images with a pod-level assertion, and a written no-manual-mutation policy. |
| S6 | Installed Prometheus, Grafana and `node_exporter` by Ansible role; diagnosed a DOWN target through service, network path and security group, and fixed it in Terraform. |
| S7 | Traced the IP-churn failure across Jenkins, k3s and Ansible; diagnosed and rolled back an `ImagePullBackOff` with zero downtime; moved 21 resources across state addresses without a destroy. |
| S8 | Demonstrated the DynamoDB lock refusing a concurrent plan with the holder named; worked a feature branch through PR review with fixup commits; documented `force-unlock` policy. |
| S9 | tfsec, Trivy, Bandit and ansible-lint in the pipeline; security groups scoped per source; a CI IAM role built from enumerated API calls; IMDSv2 required; VPC flow logs. |
| S10 | Twelve threats scored on likelihood x impact; Risk 9 and 6 items mitigated first (locking, keyless CI, SSM secrets); T8 and T9 accepted with written reasoning beside the code. |
| S11 | Nine incidents in the troubleshooting log, each in Symptom, Hypothesis, Test, Root cause, Fix, Prevention form; the 9100 timeout diagnosis ruled out one layer per test. |
| S12 | Six Ansible roles took two days to build and configure both hosts in under four minutes on every build; the cost was recovered on the second environment, which needed no new host work. |
| S15 | Thirteen-stage pipeline from push to a verified rolling update and a converged `changed=0` configuration run, authenticated by instance role. |
| S16 | Learning log covers `import` blocks, dynamic inventory over SSM, `moved` blocks, tfsec, PromQL and least privilege in CI, with five things I would do differently. |
| S17 | Python `/metrics` endpoint with `prometheus_client`, test-first, five new tests, route-based labels to bound cardinality; 20 tests at 89% coverage. |
| S20 | `ENABLE_METRICS` toggle (default off, enabled by ConfigMap) let the metrics code merge to `main` before the monitoring stack existed, extending the existing strategy-pattern toggles. |
| S21 | Modelled the target architecture with a colleague before coding; their rejection of my first option produced the private-IP/Elastic-IP split. |
| S22 | Flat root to three modules via `moved` blocks: "0 to add, 0 to change, 0 to destroy", then "No changes". |
| B1 | Opened the close-out PR with review questions, acted on all three comments, and shared the SSM inventory pattern unprompted. |
| B3 | Owned the restart incident, every alert and every red build; wrote the runbook and alert responses for whoever is on call next, including myself. |

## Reflection and Next Steps

The honest lesson is that my own gates caught my own mistakes, late. tfsec found seven problems the week it was added, three in code I had written days earlier; the least-privilege CI role failed the pipeline twice because admin credentials on my desk hid what the role could not do; a placeholder I wrote for myself was briefly stored as a secret, until I regenerated both values with `openssl rand` straight into Parameter Store. All would have been smaller had scanning been in the first commit and a PR opened before pushing to `main` alone.

What worked was the discipline of proof. "No changes" after import, "0 to destroy" after the refactor, `changed=0` on the second Ansible run and a lock refusal naming its holder are each one line of output, and each is a stronger claim than any paragraph.

The next phase moves the CRRA to a cloud-native architecture: the Flask service refactored into an AWS Lambda function consuming change requests from Amazon SQS, Jenkins replaced by AWS CodePipeline and CodeBuild, and the k3s node retired in favour of EKS or Lambda alone. The Terraform modules, remote state, threat model and runbook carry forward; only the compute beneath them changes.
