# Pipeline Setup Guide

## Prerequisites

Before setting up the Jenkins pipeline, ensure the following are installed:

1. **Jenkins** (LTS version) - `./scripts/install-jenkins.sh`
2. **Docker** - `./scripts/install-docker.sh`
3. **k3s** - `./scripts/install-k3s.sh`
4. **Trivy** - Container vulnerability scanner
   ```bash
   sudo apt-get install wget apt-transport-https gnupg lsb-release
   wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
   echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list
   sudo apt-get update && sudo apt-get install trivy
   ```

## Jenkins Configuration

### 1. Initial Setup
1. Access Jenkins at `http://<server-ip>:8080`
2. Enter the initial admin password from `/var/lib/jenkins/secrets/initialAdminPassword`
3. Install suggested plugins
4. Create an admin user

### 2. Required Plugins
- Pipeline (usually pre-installed)
- Git
- Docker Pipeline
- JUnit (for test reporting)

### 3. Tool Configuration
Navigate to Manage Jenkins → Global Tool Configuration:
- **JDK**: Java 17 (auto-install or point to local installation)
- **Git**: Default system git

## Credential Setup

### Docker Registry Credentials
1. Navigate to Manage Jenkins → Manage Credentials
2. Select the appropriate domain (Global)
3. Click "Add Credentials"
4. Kind: Username with password
5. ID: `docker-registry-credentials`
6. Username: Your Docker Hub / registry username
7. Password: Your Docker Hub / registry access token

### Kubernetes Config (if deploying from Jenkins)
1. Add credential of type "Secret file"
2. ID: `kubeconfig`
3. Upload your `~/.kube/config` file

## Pipeline Creation

### 1. Create Pipeline Job
1. Click "New Item" from Jenkins dashboard
2. Enter name: `crra-pipeline`
3. Select "Pipeline" type
4. Click OK

### 2. Configure Pipeline
1. Under "Pipeline" section:
   - Definition: Pipeline script from SCM
   - SCM: Git
   - Repository URL: Your repository URL
   - Branch Specifier: `*/main`
   - Script Path: `Jenkinsfile`
2. Under "Build Triggers":
   - Check "Poll SCM"
   - Schedule: `H/2 * * * *`
3. Click Save

### 3. First Run
1. Click "Build Now" to trigger the first pipeline run
2. Monitor the Console Output for any issues
3. Verify all stages pass (Push and Deploy only on main branch)

## Pipeline Stages Overview

| Stage | Purpose | Failure Action |
|-------|---------|----------------|
| Checkout | Clone repository | Check SCM configuration |
| Lint | Code style checks (flake8) | Fix style issues |
| Test | Run pytest with coverage | Fix failing tests |
| Security Scan | Bandit static analysis | Review security findings |
| Docker Build | Build container image | Fix Dockerfile issues |
| Trivy Scan | Container vulnerability scan | Update base image or deps |
| Push | Push to registry (main only) | Check credentials |
| Deploy | Deploy to k3s (main only) | Check k8s configuration |

## Troubleshooting

- **Pipeline not triggering**: Check SCM polling configuration and repository access
- **Docker permission denied**: Ensure Jenkins user is in docker group, restart Jenkins
- **kubectl not found**: Install kubectl on Jenkins node or configure path
- **Tests failing**: Run `pytest` locally first to reproduce
