"""Data models for the Change Request Risk Assessor."""

from dataclasses import dataclass, field
from typing import List


@dataclass
class ChangeRequest:
    """Represents a change request to be assessed for risk."""

    service_name: str
    change_type: str  # standard, normal, emergency
    blast_radius: int  # number of affected users
    time_of_day: str  # HH:MM format
    rollback_plan: bool
    service_tier: str  # tier1, tier2, tier3


@dataclass
class RiskResult:
    """Result of a risk assessment."""

    risk_level: str  # LOW, MEDIUM, HIGH, CRITICAL
    score: int  # 0-100
    factors: List[str] = field(default_factory=list)
