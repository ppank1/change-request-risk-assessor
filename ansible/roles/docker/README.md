# docker

Installs `docker.io`, writes `/etc/docker/daemon.json` (log rotation), enables the service, and adds `docker_users` to the `docker` group. Daemon config change triggers the `Restart docker` handler.

Variables: `docker_package`, `docker_users`, `docker_daemon_config`.
