"""Tests for the risk assessor core logic."""

import pytest

from risk_assessor.assessor import assess_risk


def test_low_risk_request():
    """Small blast radius, has rollback, tier3 should be LOW risk."""
    data = {
        "service_name": "test-service",
        "change_type": "standard",
        "blast_radius": 50,
        "time_of_day": "02:00",
        "rollback_plan": True,
        "service_tier": "tier3",
    }
    result = assess_risk(data)
    assert result.risk_level == "LOW"
    assert result.score < 40


def test_high_risk_no_rollback():
    """Large blast, no rollback, tier1 should be HIGH or CRITICAL."""
    data = {
        "service_name": "payment-service",
        "change_type": "normal",
        "blast_radius": 5000,
        "time_of_day": "14:00",
        "rollback_plan": False,
        "service_tier": "tier1",
    }
    result = assess_risk(data)
    assert result.risk_level in ("HIGH", "CRITICAL")
    assert result.score >= 60


def test_critical_risk_all_factors():
    """All risk factors maxed should be CRITICAL."""
    data = {
        "service_name": "core-platform",
        "change_type": "emergency",
        "blast_radius": 50000,
        "time_of_day": "12:00",
        "rollback_plan": False,
        "service_tier": "tier1",
    }
    result = assess_risk(data)
    assert result.risk_level == "CRITICAL"
    assert result.score >= 80


def test_medium_risk_mixed():
    """Some factors present should result in MEDIUM risk."""
    data = {
        "service_name": "notification-service",
        "change_type": "normal",
        "blast_radius": 1500,
        "time_of_day": "10:00",
        "rollback_plan": True,
        "service_tier": "tier2",
    }
    result = assess_risk(data)
    assert result.risk_level == "MEDIUM"
    assert 40 <= result.score < 60


def test_invalid_change_type():
    """Invalid change_type should raise ValueError."""
    data = {
        "service_name": "test-service",
        "change_type": "invalid_type",
        "blast_radius": 100,
        "time_of_day": "10:00",
        "rollback_plan": True,
        "service_tier": "tier1",
    }
    with pytest.raises(ValueError, match="Invalid change_type"):
        assess_risk(data)


def test_missing_required_field():
    """Missing required field should raise ValueError."""
    data = {
        "service_name": "test-service",
        "change_type": "standard",
    }
    with pytest.raises(ValueError, match="Missing required fields"):
        assess_risk(data)
