# monitoring

Installs `node_exporter` as a systemd service on every host (versioned download, `creates:` guard, templated unit).

Where `monitoring_server: true` (the Jenkins host) it also runs `tasks/server.yml`:

- **Prometheus** -- versioned tarball, systemd unit, `prometheus.yml` rendered from the dynamic inventory (one `node` target per host in the `crra` group by private IP, plus the app via its k3s NodePort). Config and rules are validated with `promtool` before being written; config changes reload rather than restart.
- **Alert rules** -- `TargetDown` (any `up == 0` for 2m) and `CrraHighErrorRate` (5xx > 5% for 5m).
- **Grafana** -- apt repo, `grafana.ini` with the vaulted admin password (`no_log`), provisioned Prometheus datasource and the `CRRA Overview` dashboard from `files/crra-overview.json`.

Variables: `monitoring_node_exporter_*`, `monitoring_server`, `monitoring_prometheus_*`, `monitoring_app_target_*`, `monitoring_grafana_*`. The Grafana admin password comes from `vault_grafana_admin_password`.
