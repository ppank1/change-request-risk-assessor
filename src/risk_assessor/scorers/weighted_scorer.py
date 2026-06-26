"""Weighted scoring strategy with multiplier for combined high-risk factors."""

from typing import List, Tuple

from risk_assessor.config import load_config
from risk_assessor.models import ChangeRequest
from risk_assessor.scorers.base import RiskScorer


class WeightedScorer(RiskScorer):
    """Weighted scorer with 1.2x multiplier when 3+ factors exceed individual thresholds."""

    INDIVIDUAL_THRESHOLD = 10

    def calculate_score(self, request: ChangeRequest) -> Tuple[int, List[str]]:
        config = load_config()
        score = 0
        factors = []
        high_factor_count = 0

        if config.enable_blast_radius_check:
            blast_score = 0
            if request.blast_radius > 10000:
                blast_score = 30
                factors.append("Blast radius exceeds 10000 users (+30)")
            elif request.blast_radius > 1000:
                blast_score = 20
                factors.append("Blast radius exceeds 1000 users (+20)")
            elif request.blast_radius > 100:
                blast_score = 10
                factors.append("Blast radius exceeds 100 users (+10)")
            if blast_score > self.INDIVIDUAL_THRESHOLD:
                high_factor_count += 1
            score += blast_score

        if config.enable_time_window_check:
            time_score = 0
            try:
                hour = int(request.time_of_day.split(":")[0])
                if 9 <= hour < 17:
                    time_score = 15
                    factors.append("Change during peak hours 09:00-17:00 (+15)")
            except (ValueError, IndexError):
                pass
            if time_score > self.INDIVIDUAL_THRESHOLD:
                high_factor_count += 1
            score += time_score

        if config.enable_rollback_check:
            rollback_score = 0
            if not request.rollback_plan:
                rollback_score = 25
                factors.append("No rollback plan defined (+25)")
            if rollback_score > self.INDIVIDUAL_THRESHOLD:
                high_factor_count += 1
            score += rollback_score

        # Service tier scoring
        tier_score = 0
        if request.service_tier == "tier1":
            tier_score = 20
            factors.append("Tier 1 critical service (+20)")
        elif request.service_tier == "tier2":
            tier_score = 10
            factors.append("Tier 2 service (+10)")
        if tier_score > self.INDIVIDUAL_THRESHOLD:
            high_factor_count += 1
        score += tier_score

        # Change type scoring
        type_score = 0
        if request.change_type == "emergency":
            type_score = 15
            factors.append("Emergency change type (+15)")
        elif request.change_type == "normal":
            type_score = 5
            factors.append("Normal change type (+5)")
        if type_score > self.INDIVIDUAL_THRESHOLD:
            high_factor_count += 1
        score += type_score

        # Apply multiplier if 3+ factors exceed individual thresholds
        if high_factor_count >= 3:
            score = int(score * 1.2)
            factors.append(f"Combined risk multiplier applied (1.2x, {high_factor_count} high factors)")

        return min(score, 100), factors
