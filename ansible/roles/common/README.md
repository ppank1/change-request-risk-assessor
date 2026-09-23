# common

Baseline for every CRRA host: packages, timezone, unattended security upgrades, and `/etc/crra/environment` (rendered from a vaulted token, `no_log`).

Variables (`defaults/main.yml`): `common_packages`, `common_timezone`, `common_apt_cache_valid_time`, `common_crra_api_token` (from `vault_crra_api_token`).
