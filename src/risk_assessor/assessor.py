"""Main risk assessment logic."""

import re

from risk_assessor.config import load_config
from risk_assessor.models import ChangeRequest, RiskResult
from risk_assessor.scorers import get_scorer

VALID_CHANGE_TYPES = {"standard", "normal", "emergency"}
VALID_SERVICE_TIERS = {"tier1", "tier2", "tier3"}
REQUIRED_FIELDS = {"service_name", "change_type", "blast_radius", "time_of_day", "rollback_plan", "service_tier"}
TIME_PATTERN = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


def assess_risk(data: dict) -> RiskResult:
    """Assess risk for a change request.

    Args:
        data: Dictionary containing change request fields.

    Returns:
        RiskResult with risk level, score, and contributing factors.

    Raises:
        ValueError: If required fields are missing or values are invalid.
    """
    # Validate required fields
    missing = REQUIRED_FIELDS - set(data.keys())
    if missing:
        raise ValueError(f"Missing required fields: {', '.join(sorted(missing))}")

    # Validate field values
    if data["change_type"] not in VALID_CHANGE_TYPES:
        raise ValueError(f"Invalid change_type: {data['change_type']}. Must be one of: {VALID_CHANGE_TYPES}")

    if data["service_tier"] not in VALID_SERVICE_TIERS:
        raise ValueError(f"Invalid service_tier: {data['service_tier']}. Must be one of: {VALID_SERVICE_TIERS}")

    if not TIME_PATTERN.match(str(data["time_of_day"])):
        raise ValueError(f"Invalid time_of_day format: {data['time_of_day']}. Must be HH:MM (24-hour)")

    # Build change request model
    request = ChangeRequest(
        service_name=data["service_name"],
        change_type=data["change_type"],
        blast_radius=int(data["blast_radius"]),
        time_of_day=data["time_of_day"],
        rollback_plan=bool(data["rollback_plan"]),
        service_tier=data["service_tier"],
    )

    # Load scorer and calculate
    config = load_config()
    scorer = get_scorer(config.scoring_strategy)
    score, factors = scorer.calculate_score(request)

    # Map score to risk level
    if score >= config.critical_risk_threshold:
        risk_level = "CRITICAL"
    elif score >= config.high_risk_threshold:
        risk_level = "HIGH"
    elif score >= 40:
        risk_level = "MEDIUM"
    else:
        risk_level = "LOW"

    return RiskResult(risk_level=risk_level, score=score, factors=factors)
