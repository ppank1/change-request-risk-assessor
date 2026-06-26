"""Flask application for the Change Request Risk Assessor."""

import json
import logging
import sys
from dataclasses import asdict

from flask import Flask, jsonify, request

from risk_assessor import __version__
from risk_assessor.assessor import assess_risk
from risk_assessor.config import load_config

# Configure structured JSON logging
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(logging.Formatter(json.dumps({
    "timestamp": "%(asctime)s",
    "level": "%(levelname)s",
    "message": "%(message)s",
    "module": "%(module)s",
})))

logger = logging.getLogger(__name__)
logger.addHandler(handler)


def create_app():
    """Application factory."""
    app = Flask(__name__)
    config = load_config()
    logger.setLevel(getattr(logging, config.log_level, logging.INFO))

    @app.route("/health", methods=["GET"])
    def health():
        return jsonify({
            "status": "healthy",
            "version": __version__,
            "scoring_strategy": config.scoring_strategy,
        }), 200

    @app.route("/assess", methods=["POST"])
    def assess():
        if not request.is_json:
            return jsonify({"error": "Request must be JSON"}), 400

        data = request.get_json()
        try:
            result = assess_risk(data)
            return jsonify(asdict(result)), 200
        except ValueError as e:
            logger.warning("Validation error: %s", str(e))
            return jsonify({"error": str(e)}), 400
        except Exception as e:
            logger.error("Internal error: %s", str(e))
            return jsonify({"error": "Internal server error"}), 500

    return app


if __name__ == "__main__":
    app = create_app()
    app.run(host="0.0.0.0", port=5000)
