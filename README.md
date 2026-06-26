# Change Request Risk Assessor (CRRA)

An automated risk scoring system for change requests, built as a Python/Flask microservice with CI/CD pipeline and Kubernetes deployment.

## Quick Start

```bash
# Install dependencies
pip install -r requirements.txt
pip install -e .

# Run tests
pytest

# Run the application
python -m risk_assessor.app
```

The service will be available at `http://localhost:5000`.

## API Endpoints

### POST /assess
Submit a change request for risk assessment.

```json
{
  "service_name": "payment-service",
  "change_type": "normal",
  "blast_radius": 5000,
  "time_of_day": "14:00",
  "rollback_plan": true,
  "service_tier": "tier1"
}
```

Response:
```json
{
  "risk_level": "MEDIUM",
  "score": 45,
  "factors": ["Blast radius exceeds 1000 users (+20)", "Tier 1 critical service (+20)", "Normal change type (+5)"]
}
```

### GET /health
Health check endpoint returning service status.

## Architecture

The system uses a **strategy pattern** for scoring, allowing different scoring algorithms to be swapped via configuration:

- **SimpleScorer**: Fixed point addition per risk dimension
- **WeightedScorer**: Weighted scoring with multiplier for combined high-risk factors

Feature toggles allow individual risk checks to be enabled/disabled at runtime via environment variables.

See [docs/architecture.md](docs/architecture.md) for detailed architecture documentation.

## Testing

```bash
# Run all tests with coverage
pytest

# Run specific test file
pytest tests/test_assessor.py

# Run with verbose output
pytest -v
```

## Deployment

### Docker
```bash
docker build -t crra .
docker run -p 5000:5000 crra
```

### Kubernetes (k3s)
```bash
./scripts/deploy.sh
```

### CI/CD Pipeline
The Jenkinsfile defines a complete pipeline: Lint → Test → Security Scan → Docker Build → Trivy Scan → Push → Deploy.

See [docs/pipeline-setup-guide.md](docs/pipeline-setup-guide.md) for setup instructions.

## Configuration

All configuration is via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| SCORING_STRATEGY | simple | Scoring algorithm: simple or weighted |
| ENABLE_BLAST_RADIUS_CHECK | true | Toggle blast radius scoring |
| ENABLE_TIME_WINDOW_CHECK | true | Toggle peak hours scoring |
| ENABLE_ROLLBACK_CHECK | true | Toggle rollback plan scoring |
| HIGH_RISK_THRESHOLD | 60 | Score threshold for HIGH risk |
| CRITICAL_RISK_THRESHOLD | 80 | Score threshold for CRITICAL risk |
| LOG_LEVEL | INFO | Application log level |

## Contributing

1. Create a feature branch
2. Write tests first (TDD)
3. Implement the feature
4. Ensure all tests pass: `pytest`
5. Run linting: `flake8 src/ tests/`
6. Run security scan: `bandit -r src/`
7. Submit a code review
