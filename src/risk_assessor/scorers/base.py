"""Abstract base class for risk scorers."""

from abc import ABC, abstractmethod
from typing import List, Tuple

from risk_assessor.models import ChangeRequest


class RiskScorer(ABC):
    """Abstract base class defining the scoring interface."""

    @abstractmethod
    def calculate_score(self, request: ChangeRequest) -> Tuple[int, List[str]]:
        """Calculate risk score for a change request.

        Returns:
            Tuple of (score, list of contributing factor descriptions)
        """
        pass
