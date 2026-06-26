# Architecture

## Overview

The Change Request Risk Assessor (CRRA) is a microservice that evaluates change requests against multiple risk dimensions and returns a risk score with explanatory factors. It is designed to integrate into CI/CD pipelines and change management workflows.

## Components

```
┌─────────────────────────────────────────────────┐
│                 Flask API Layer                   │
│           (app.py - /assess, /health)            │
├─────────────────────────────────────────────────┤
│              Risk Assessor Engine                 │
│         (assessor.py - validation, orchestration)│
├─────────────────────────────────────────────────┤
│             Scoring Strategy Layer                │
│  ┌──────────────────┐  ┌──────────────────────┐ │
│  │  SimpleScorer     │  │  WeightedScorer       │ │
│  │  (fixed points)   │  │  (weights+multiplier) │ │
│  └──────────────────┘  └──────────────────────┘ │
├─────────────────────────────────────────────────┤
│           Configuration Layer                    │
│    (config.py - env vars, feature toggles)       │
└─────────────────────────────────────────────────┘
```

## Data Flow

1. Client sends POST /assess with change request JSON
2. Flask route handler passes data to `assess_risk()`
3. Assessor validates required fields and field values
4. Assessor loads the configured scoring strategy
5. Scorer evaluates each enabled risk dimension
6. Assessor maps total score to risk level (LOW/MEDIUM/HIGH/CRITICAL)
7. RiskResult returned as JSON to client

## Design Decisions

- **Strategy Pattern**: Scoring algorithms are interchangeable via configuration, enabling A/B testing and gradual rollout of new scoring logic.
- **Feature Toggles**: Individual risk checks can be disabled without code changes, enabling safe experimentation.
- **Dataclasses**: Immutable data models enforce type safety and provide clear contracts.
- **Environment Configuration**: No hardcoded values; all tunables are configurable at deploy time.
- **Multi-stage Docker Build**: Minimises image size and attack surface.

## Deployment Architecture

```
Jenkins Pipeline → Docker Image → Container Registry → k3s Cluster
                                                        ├── crra-dev namespace
                                                        │   ├── Deployment (2 replicas)
                                                        │   ├── Service (ClusterIP:5000)
                                                        │   └── ConfigMap (feature toggles)
                                                        └── crra-staging namespace
```
