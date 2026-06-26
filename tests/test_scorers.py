"""Tests for scoring strategies."""

from risk_assessor.models import ChangeRequest
from risk_assessor.scorers import get_scorer
from risk_assessor.scorers.simple_scorer import SimpleScorer
from risk_assessor.scorers.weighted_scorer import WeightedScorer


def test_simple_scorer_calculation():
    """SimpleScorer should add fixed points for each risk dimension."""
    scorer = SimpleScorer()
    request = ChangeRequest(
        service_name="test",
        change_type="emergency",
        blast_radius=15000,
        time_of_day="14:00",
        rollback_plan=False,
        service_tier="tier1",
    )
    score, factors = scorer.calculate_score(request)
    # blast > 10000: +30, peak hours: +15, no rollback: +25, tier1: +20, emergency: +15 = 105 -> capped at 100
    assert score == 100
    assert len(factors) == 5


def test_weighted_scorer_multiplier():
    """WeightedScorer should apply 1.2x multiplier when 3+ factors exceed threshold."""
    scorer = WeightedScorer()
    request = ChangeRequest(
        service_name="test",
        change_type="emergency",
        blast_radius=15000,
        time_of_day="14:00",
        rollback_plan=False,
        service_tier="tier1",
    )
    score, factors = scorer.calculate_score(request)
    # Multiple high factors should trigger multiplier
    assert any("multiplier" in f for f in factors)
    assert score == 100  # Capped at 100


def test_scorer_factory():
    """get_scorer should return correct scorer based on strategy name."""
    simple = get_scorer("simple")
    assert isinstance(simple, SimpleScorer)

    weighted = get_scorer("weighted")
    assert isinstance(weighted, WeightedScorer)
