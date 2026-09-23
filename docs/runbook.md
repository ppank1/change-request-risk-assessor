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
- A stuck lock (`Error acquiring the state lock`) after a crashed run: confirm no one is applying, then `terraform force-unlock <LOCK_ID>`.
- Recovering a bad state write: S3 versioning keeps every prior state — download the previous version and `terraform state push`.

## Routine checks

| Check | Command | Expect |
|---|---|---|
| Drift | `terraform plan -var-file=dev.tfvars` | `No changes.` — anything else is drift or an unlanded change |
| Hosts up | `aws ec2 describe-instances --filters Name=tag:Project,Values=crra --query 'Reservations[].Instances[].[Tags[?Key==\`Name\`]\|[0].Value,State.Name]' --output table` | all `running` |
| Config drift inside hosts | `ansible-playbook playbooks/site.yml --check` | `changed=0` |

## Adding a new host

1. Add the instance and its EIP to `modules/compute`, its security group to `modules/security`.
2. `terraform plan` — review that only the new resources are added.
3. `terraform apply`.
4. Tag it `Role=<role>`; the Ansible dynamic inventory picks it up with no inventory edit.
5. `ansible-playbook playbooks/site.yml --limit <role>`.
