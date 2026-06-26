"""Scoring strategy implementations."""

from risk_assessor.scorers.simple_scorer import SimpleScorer
from risk_assessor.scorers.weighted_scorer import WeightedScorer


def get_scorer(strategy: str):
    """Factory function to return the appropriate scorer based on strategy name."""
    scorers = {
        "simple": SimpleScorer,
        "weighted": WeightedScorer,
    }
    scorer_class = scorers.get(strategy)
    if scorer_class is None:
        raise ValueError(f"Unknown scoring strategy: {strategy}")
    return scorer_class()
