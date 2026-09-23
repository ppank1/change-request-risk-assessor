"""Prometheus metrics for the risk assessor.

Exposes a /metrics endpoint in the text exposition format and records
per-request counters and latency. Registered only when ENABLE_METRICS is true,
so the toggle removes the endpoint entirely rather than serving an empty page.
"""

import time

from flask import Response, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Histogram,
    generate_latest,
)


def register_metrics(app):
    """Attach request instrumentation and a /metrics route to a Flask app.

    A private registry is used so each app instance (and each test) starts
    from zero instead of sharing process-global collectors.
    """
    registry = CollectorRegistry()

    requests_total = Counter(
        "crra_http_requests_total",
        "HTTP requests handled, by method, endpoint and status code.",
        ["method", "endpoint", "status"],
        registry=registry,
    )
    request_duration = Histogram(
        "crra_http_request_duration_seconds",
        "HTTP request latency in seconds, by endpoint.",
        ["endpoint"],
        registry=registry,
    )
    assessments_total = Counter(
        "crra_assessments_total",
        "Successful risk assessments, by resulting risk level.",
        ["risk_level"],
        registry=registry,
    )

    @app.before_request
    def _start_timer():
        request._crra_start = time.perf_counter()

    @app.after_request
    def _record(response):
        # The scrape itself is not application traffic.
        if request.path == "/metrics":
            return response
        # Use the matched route so unknown paths do not create unbounded labels.
        endpoint = request.url_rule.rule if request.url_rule else "unmatched"
        requests_total.labels(request.method, endpoint, str(response.status_code)).inc()
        request_duration.labels(endpoint).observe(time.perf_counter() - request._crra_start)
        return response

    @app.route("/metrics", methods=["GET"])
    def metrics():
        return Response(generate_latest(registry), mimetype=CONTENT_TYPE_LATEST)

    # Handed to the app so business code can count without importing globals.
    app.extensions["crra_metrics"] = {"assessments_total": assessments_total}


def record_assessment(app, risk_level):
    """Count one successful assessment; a no-op when metrics are disabled."""
    metrics = app.extensions.get("crra_metrics")
    if metrics:
        metrics["assessments_total"].labels(risk_level).inc()
