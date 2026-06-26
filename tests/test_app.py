"""Tests for the Flask application endpoints."""

import json

import pytest

from risk_assessor.app import create_app


@pytest.fixture
def client():
    """Create test client."""
    app = create_app()
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_health_endpoint(client):
    """GET /health should return 200 with status."""
    response = client.get("/health")
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data["status"] == "healthy"
    assert data["version"] == "1.0.0"
    assert "scoring_strategy" in data


def test_assess_valid_request(client):
    """POST /assess with valid data should return risk result."""
    payload = {
        "service_name": "test-service",
        "change_type": "standard",
        "blast_radius": 50,
        "time_of_day": "02:00",
        "rollback_plan": True,
        "service_tier": "tier3",
    }
    response = client.post("/assess", json=payload)
    assert response.status_code == 200
    data = json.loads(response.data)
    assert "risk_level" in data
    assert "score" in data
    assert "factors" in data


def test_assess_invalid_request(client):
    """POST /assess with invalid change_type should return 400."""
    payload = {
        "service_name": "test-service",
        "change_type": "invalid",
        "blast_radius": 50,
        "time_of_day": "02:00",
        "rollback_plan": True,
        "service_tier": "tier3",
    }
    response = client.post("/assess", json=payload)
    assert response.status_code == 400
    data = json.loads(response.data)
    assert "error" in data


def test_assess_missing_fields(client):
    """POST /assess with missing fields should return 400."""
    payload = {"service_name": "test-service"}
    response = client.post("/assess", json=payload)
    assert response.status_code == 400
    data = json.loads(response.data)
    assert "error" in data
