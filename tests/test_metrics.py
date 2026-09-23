"""Tests for the Prometheus /metrics endpoint and its feature toggle."""

import os

import pytest

from risk_assessor.app import create_app


def _client(enable_metrics):
    os.environ["ENABLE_METRICS"] = enable_metrics
    try:
        app = create_app()
    finally:
        del os.environ["ENABLE_METRICS"]
    app.config["TESTING"] = True
    return app.test_client()


@pytest.fixture
def client():
    """Client with metrics enabled (the default)."""
    return _client("true")


def test_metrics_endpoint_exposes_prometheus_format(client):
    """GET /metrics should return the Prometheus text exposition format."""
    response = client.get("/metrics")
    assert response.status_code == 200
    assert response.content_type.startswith("text/plain")
    body = response.data.decode()
    assert "crra_http_requests_total" in body
    assert "crra_http_request_duration_seconds" in body


def test_metrics_count_requests_by_endpoint_and_status(client):
    """Requests are counted with method, endpoint and status labels."""
    client.get("/health")
    client.post("/assess", json={"service_name": "x"})  # 400
    body = client.get("/metrics").data.decode()
    assert 'crra_http_requests_total{endpoint="/health",method="GET",status="200"}' in body
    assert 'crra_http_requests_total{endpoint="/assess",method="POST",status="400"}' in body


def test_metrics_count_assessments_by_risk_level(client):
    """Successful assessments are counted per resulting risk level."""
    payload = {
        "service_name": "test-service",
        "change_type": "standard",
        "blast_radius": 50,
        "time_of_day": "02:00",
        "rollback_plan": True,
        "service_tier": "tier3",
    }
    assert client.post("/assess", json=payload).status_code == 200
    body = client.get("/metrics").data.decode()
    assert 'crra_assessments_total{risk_level="LOW"}' in body


def test_metrics_not_counted_for_scrape_itself(client):
    """Scraping /metrics must not inflate the request counter."""
    client.get("/metrics")
    body = client.get("/metrics").data.decode()
    assert 'endpoint="/metrics"' not in body


def test_metrics_disabled_by_toggle():
    """ENABLE_METRICS=false removes the endpoint entirely."""
    client = _client("false")
    assert client.get("/metrics").status_code == 404
    assert client.get("/health").status_code == 200
