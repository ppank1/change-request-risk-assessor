# hardening

SSH drop-in (`/etc/ssh/sshd_config.d/99-crra-hardening.conf`: no root login, no passwords, `MaxAuthTries 4`, validated with `sshd -t` before install), fail2ban, and kernel network sysctls in `/etc/sysctl.d/99-crra-hardening.conf`. SSH config change triggers `Restart sshd`.

Variables: `hardening_ssh_*`, `hardening_fail2ban_enabled`, `hardening_sysctl`.
