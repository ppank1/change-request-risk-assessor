"""Simple additive scoring strategy."""

from typing import List, Tuple

from risk_assessor.config import load_config
from risk_assessor.models import ChangeRequest
from risk_assessor.scorers.base import RiskScorer


class SimpleScorer(RiskScorer):
    """Each risk dimension adds fixed points to the total score."""

    def calculate_score(self, request: ChangeRequest) -> Tuple[int, List[str]]:
        config = load_config()
        score = 0
        factors = []

        if config.enable_blast_radius_check:
            if request.blast_radius > 10000:
                score += 30
                factors.append("Blast radius exceeds 10000 users (+30)")
            elif request.blast_radius > 1000:
                score += 20
                factors.append("Blast radius exceeds 1000 users (+20)")
            elif request.blast_radius > 100:
                score += 10
                factors.append("Blast radius exceeds 100 users (+10)")

        if config.enable_time_window_check:
            try:
                hour = int(request.time_of_day.split(":")[0])
                if 9 <= hour < 17:
                    score += 15
                    factors.append("Change during peak hours 09:00-17:00 (+15)")
            except (ValueError, IndexError):
                pass

        if config.enable_rollback_check:
            if not request.rollback_plan:
                score += 25
                factors.append("No rollback plan defined (+25)")

        # Service tier scoring (always enabled)
        if request.service_tier == "tier1":
            score += 20
            factors.append("Tier 1 critical service (+20)")
        elif request.service_tier == "tier2":
            score += 10
            factors.append("Tier 2 service (+10)")

        # Change type scoring (always enabled)
        if request.change_type == "emergency":
            score += 15
            factors.append("Emergency change type (+15)")
        elif request.change_type == "normal":
            score += 5
            factors.append("Normal change type (+5)")

        return min(score, 100), factors
