"""Tests for configuration loading."""

import os

from risk_assessor.config import load_config


def test_default_config():
    """Defaults should be loaded when no env vars are set."""
    # Clear any existing env vars
    env_vars = ["SCORING_STRATEGY", "ENABLE_BLAST_RADIUS_CHECK", "ENABLE_TIME_WINDOW_CHECK",
                "ENABLE_ROLLBACK_CHECK", "HIGH_RISK_THRESHOLD", "CRITICAL_RISK_THRESHOLD", "LOG_LEVEL"]
    original = {k: os.environ.pop(k, None) for k in env_vars}

    try:
        config = load_config()
        assert config.scoring_strategy == "simple"
        assert config.enable_blast_radius_check is True
        assert config.enable_time_window_check is True
        assert config.enable_rollback_check is True
        assert config.high_risk_threshold == 60
        assert config.critical_risk_threshold == 80
        assert config.log_level == "INFO"
    finally:
        for k, v in original.items():
            if v is not None:
                os.environ[k] = v


def test_custom_config():
    """Environment variables should override defaults."""
    os.environ["SCORING_STRATEGY"] = "weighted"
    os.environ["ENABLE_BLAST_RADIUS_CHECK"] = "false"
    os.environ["HIGH_RISK_THRESHOLD"] = "70"
    os.environ["LOG_LEVEL"] = "DEBUG"

    try:
        config = load_config()
        assert config.scoring_strategy == "weighted"
        assert config.enable_blast_radius_check is False
        assert config.high_risk_threshold == 70
        assert config.log_level == "DEBUG"
    finally:
        del os.environ["SCORING_STRATEGY"]
        del os.environ["ENABLE_BLAST_RADIUS_CHECK"]
        del os.environ["HIGH_RISK_THRESHOLD"]
        del os.environ["LOG_LEVEL"]
