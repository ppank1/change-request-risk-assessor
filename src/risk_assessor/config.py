"""Configuration loading from environment variables."""

import os


class Config:
    """Application configuration loaded from environment variables with defaults."""

    def __init__(self):
        self.scoring_strategy = os.environ.get("SCORING_STRATEGY", "simple")
        self.enable_blast_radius_check = os.environ.get("ENABLE_BLAST_RADIUS_CHECK", "true").lower() == "true"
        self.enable_time_window_check = os.environ.get("ENABLE_TIME_WINDOW_CHECK", "true").lower() == "true"
        self.enable_rollback_check = os.environ.get("ENABLE_ROLLBACK_CHECK", "true").lower() == "true"
        self.high_risk_threshold = int(os.environ.get("HIGH_RISK_THRESHOLD", "60"))
        self.critical_risk_threshold = int(os.environ.get("CRITICAL_RISK_THRESHOLD", "80"))
        self.log_level = os.environ.get("LOG_LEVEL", "INFO")


def load_config() -> Config:
    """Load and return application configuration."""
    return Config()
