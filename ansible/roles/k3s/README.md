# k3s

Installs k3s (guarded by `creates:` so it is a no-op on an existing node), writes `/etc/rancher/k3s/config.yaml` advertising the private IP, enables the service, waits for the API, and distributes the kubeconfig to `k3s_kubeconfig_users`. Config change triggers `Restart k3s`.

Variables: `k3s_install_url`, `k3s_config_dir`, `k3s_kubeconfig_users`. Uses the inventory-composed `private_ip`.
