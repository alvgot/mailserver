#!/bin/bash

# Add missing security components
cat >> ansible-mailserver/roles/mailserver/tasks/main.yml <<EOF
- include_tasks: aide.yml
- include_tasks: redis.yml
EOF

# Add AIDE configuration
mkdir -p ansible-mailserver/roles/mailserver/templates/aide
cat > ansible-mailserver/roles/mailserver/templates/aide/aide.conf.j2 <<EOF
/etc p+i+u+g+sha512
/var/mail p+i+u+g+sha512
EOF

# Update group_vars
cat >> ansible-mailserver/group_vars/all.yml <<EOF
redis_password: "{{ 24 | random_password }}"
backup_passphrase: "{{ 50 | random_password }}"
EOF

echo "Critical security gaps patched!"
