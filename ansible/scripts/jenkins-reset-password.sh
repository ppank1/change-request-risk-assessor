#!/bin/bash
# Break-glass: reset a Jenkins local-user password without disabling security.
# Runs ON the Jenkins host via Ansible (over SSM):
#   ansible crra-jenkins-001 -m script -a "scripts/jenkins-reset-password.sh <user> <new-password>"
# Writes a bcrypt hash into the user's config.xml (backup kept) and restarts Jenkins.
set -euo pipefail

USER_NAME="${1:?usage: $0 <username (without the _hash suffix)> <new-password>}"
NEW_PW="${2:?usage: $0 <username> <new-password>}"
JENKINS_HOME=/var/lib/jenkins

USER_DIR=$(ls -d "${JENKINS_HOME}/users/${USER_NAME}"_* 2>/dev/null | head -1 || true)
if [ -z "${USER_DIR}" ]; then
  echo "No Jenkins user '${USER_NAME}'. Known users (pass the name without the _suffix):"
  ls "${JENKINS_HOME}/users" | grep -v '^users.xml$' | sed 's/_[0-9a-f]*$//'
  exit 1
fi

DEBIAN_FRONTEND=noninteractive apt-get install -y -q python3-bcrypt >/dev/null

# Jenkins' jbcrypt expects the $2a$ prefix; python-bcrypt emits $2b$ (same algorithm).
HASH=$(NEW_PW="${NEW_PW}" python3 - <<'EOF'
import bcrypt, os
h = bcrypt.hashpw(os.environ["NEW_PW"].encode(), bcrypt.gensalt(10)).decode()
print(h.replace("$2b$", "$2a$", 1))
EOF
)

cp "${USER_DIR}/config.xml" "${USER_DIR}/config.xml.bak-$(date +%s)"
sed -i "s|<passwordHash>[^<]*</passwordHash>|<passwordHash>#jbcrypt:${HASH}</passwordHash>|" "${USER_DIR}/config.xml"
grep -q "#jbcrypt:${HASH}" "${USER_DIR}/config.xml"

systemctl restart jenkins
echo "Password reset for '${USER_NAME}' (${USER_DIR}); Jenkins restarted."
