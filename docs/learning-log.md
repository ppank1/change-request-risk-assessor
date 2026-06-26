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
