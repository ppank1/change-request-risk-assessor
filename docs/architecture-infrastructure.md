# CRRA Infrastructure Architecture — Target State

This document describes where the CRRA infrastructure is going: from two hand-built EC2 instances to infrastructure that is codified (Terraform), configured by code (Ansible), rebuilt rather than patched, and monitored at both the host and application level.

For the application architecture (scoring strategies, feature toggles) see [architecture.md](architecture.md).

## Diagram

```mermaid
flowchart TB
    Eng["Engineer / Jenkins agent<br/>terraform · ansible · kubectl"]

    subgraph State["Terraform remote state"]
        S3["S3 bucket<br/>versioned · encrypted · no public access"]
        DDB["DynamoDB lock table<br/>LockID"]
    end

    subgraph VPC["AWS us-west-2 · default VPC 172.31.0.0/16"]
        subgraph Subnet["Subnet us-west-2a"]
            subgraph J["crra-jenkins-001 · t3.medium · EIP"]
                Jenkins["Jenkins :8080"]
                Docker["Docker"]
                Prom["Prometheus :9090"]
                Graf["Grafana :3000"]
                NEJ["node_exporter :9100"]
            end
            subgraph K["crra-k3s-001 · t3.small · EIP"]
                K3s["k3s API :6443"]
                App["CRRA pods<br/>/health · /metrics"]
                NEK["node_exporter :9100"]
            end
        end
        SSM["SSM Parameter Store<br/>AWS-side secrets"]
    end

    Eng -- "terraform plan / apply" --> State
    State -. "creates / replaces" .-> VPC
    Eng -- "ansible-playbook<br/>dynamic inventory (aws_ec2 plugin, by tag)" --> J
    Eng -- "ansible-playbook" --> K
    Jenkins -- "kubectl apply<br/>private IP :6443" --> K3s
    K3s --> App
    Docker -- "image tagged by commit SHA" --> App
    Prom -- "scrape :9100" --> NEJ
    Prom -- "scrape :9100" --> NEK
    Prom -- "scrape /metrics" --> App
    Graf --> Prom
    Jenkins -. "reads" .-> SSM
```

## Layers

**Terraform** owns every AWS resource: VPC and subnet (imported, not recreated), security groups, Elastic IPs, both instances, IAM roles, SSM parameters, and the state backend itself. Code is split into `network`, `compute`, `security` and `monitoring` modules with one root config per environment (`dev`, `staging`), so the same modules produce both environments from different `.tfvars`.

**Remote state** lives in S3 (versioned, encrypted, public access blocked) with a DynamoDB table for locking, so two engineers — or an engineer and the pipeline — cannot corrupt state by applying at the same time.

**Ansible** owns everything inside the instances via roles (`common`, `docker`, `jenkins`, `k3s`, `monitoring`, `hardening`). Inventory is dynamic: the `amazon.aws.aws_ec2` plugin selects hosts by tag, so the Phase 0 failure mode — configuration holding a public IP that changes on restart — cannot recur. Secrets are in Ansible Vault (in-repo) and SSM Parameter Store (AWS-side).

**Immutability.** Instances are not patched in place. Configuration is applied by Ansible, and when the base image or host config changes the instance is replaced with `terraform apply -replace`. Container images are tagged by git commit SHA so a running pod can always be traced to the exact code that built it; `:latest` is not used.

**Monitoring.** Prometheus and Grafana run on the Jenkins host. `node_exporter` on both hosts covers CPU, memory, disk and network. The CRRA Flask app exposes `/metrics` so request rate, latency and error rate are scraped from the application itself, not inferred from the box. One alert rule fires on application error rate.

**Deploy path.** Jenkins builds and tests the app, builds a SHA-tagged image, then runs `kubectl apply` against the k3s API over the instance's **private** IP on 6443. Private IPs are stable across stop/start, which is why this path survived the Phase 0 restart when the public-IP-based configuration did not.

## Design decisions

| Decision | Alternative considered | Why this |
|---|---|---|
| Import the existing VPC/subnet/instances rather than recreate | Destroy and rebuild from scratch | Keeps the working Jenkins and k3s state; import blocks give a reviewable plan proving the code matches reality before anything changes |
| Elastic IPs on both instances | Fix the Jenkins URL by hand after each restart | Removes the root cause of the Phase 0 incident instead of the symptom |
| Dynamic inventory by tag | Static `hosts.ini` | Static inventory holds IPs; IPs are exactly what changed |
| Prometheus on the Jenkins host | Separate monitoring instance | Two instances is the budget; Jenkins host is the larger one |
| SHA-tagged images | `:latest` | `:latest` made rollback and "what is actually running" unanswerable |
