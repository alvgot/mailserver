#!/bin/bash
set -e

BASE_DIR="ansible-mailserver"

# Create missing directories
mkdir -p ${BASE_DIR}/roles/mailserver/{templates/{prometheus,grafana,aide,redis,logrotate,spamassassin,roundcube/plugins/password},tasks,handlers}

# 1. Monitoring Stack Implementation
cat > ${BASE_DIR}/roles/mailserver/templates/prometheus/alerts.yml.j2 <<'EOF'
groups:
- name: mailserver
  rules:
  - alert: HighLoad
    expr: node_load15 > 2
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High load on {{ inventory_hostname }}"
  - alert: ServiceDown
    expr: up{job="mailserver"} == 0
    for: 1m
    labels:
      severity: critical
EOF

cat > ${BASE_DIR}/roles/mailserver/templates/grafana/datasources.yml.j2 <<'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF

# 2. Security Enhancements
cat > ${BASE_DIR}/roles/mailserver/templates/aide/aide.conf.j2 <<'EOF'
@@define DBDIR /var/lib/aide
@@define LOGDIR /var/log/aide

# Critical system files
/etc p+i+u+g+sha512
/bin p+i+u+g+sha512
/usr/bin p+i+u+g+sha512
/var/mail p+i+u+g+sha512
EOF

cat > ${BASE_DIR}/roles/mailserver/templates/redis/redis.conf.j2 <<'EOF'
bind 127.0.0.1
protected-mode yes
requirepass {{ redis_password }}
maxmemory 512mb
maxmemory-policy allkeys-lru
EOF

# 3. Webmail Enhancements
cat > ${BASE_DIR}/roles/mailserver/templates/roundcube/plugins/password/config.inc.php.j2 <<'EOF'
<?php
$config['password_minimum_length'] = 12;
$config['password_require_nonalpha'] = true;
$config['password_force_new_password'] = true;
EOF

# 4. Automatic Updates
cat > ${BASE_DIR}/roles/mailserver/templates/auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
EOF

# 5. Log Management
cat > ${BASE_DIR}/roles/mailserver/templates/logrotate/mailserver <<'EOF'
/var/log/mail.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    sharedscripts
    postrotate
        systemctl reload postfix dovecot
    endscript
}

/var/log/suricata/*.log {
    weekly
    rotate 8
    compress
}
EOF

# 6. Certificate Management
cat > ${BASE_DIR}/roles/mailserver/templates/caddy-renewal.cron.j2 <<'EOF'
0 3 * * * /usr/bin/caddy reload --config /etc/caddy/Caddyfile
EOF

# 7. Task Files
cat > ${BASE_DIR}/roles/mailserver/tasks/monitoring.yml <<'EOF'
---
- name: Install monitoring stack
  apt:
    name: ["prometheus", "grafana", "prometheus-node-exporter"]
    state: present

- name: Deploy monitoring configurations
  template:
    src: "{{ item.src }}"
    dest: "{{ item.dest }}"
  loop:
    - { src: 'prometheus/prometheus.yml.j2', dest: '/etc/prometheus/prometheus.yml' }
    - { src: 'prometheus/alerts.yml.j2', dest: '/etc/prometheus/alert_rules.yml' }
    - { src: 'grafana/datasources.yml.j2', dest: '/etc/grafana/provisioning/datasources/prometheus.yml' }
  notify: restart monitoring services

- name: Enable monitoring services
  systemd:
    name: "{{ item }}"
    enabled: yes
    state: started
  loop:
    - prometheus
    - grafana
    - prometheus-node-exporter
EOF

cat > ${BASE_DIR}/roles/mailserver/tasks/aide.yml <<'EOF'
---
- name: Install and configure AIDE
  apt:
    name: aide
    state: present
  notify: initialize aide

- name: Deploy AIDE config
  template:
    src: aide/aide.conf.j2
    dest: /etc/aide/aide.conf
EOF

cat > ${BASE_DIR}/roles/mailserver/tasks/redis.yml <<'EOF'
---
- name: Install and secure Redis
  apt:
    name: redis-server
    state: present

- name: Configure Redis
  template:
    src: redis/redis.conf.j2
    dest: /etc/redis/redis.conf
  notify: restart redis
EOF

# 8. Handlers
cat > ${BASE_DIR}/roles/mailserver/handlers/main.yml <<'EOF'
---
- name: restart monitoring services
  systemd:
    name: "{{ item }}"
    state: restarted
  loop:
    - prometheus
    - grafana

- name: restart redis
  systemd:
    name: redis-server
    state: restarted

- name: initialize aide
  command: aideinit -y -f
EOF

# 9. Update Main Configuration
cat >> ${BASE_DIR}/roles/mailserver/tasks/main.yml <<'EOF'
- include_tasks: monitoring.yml
- include_tasks: aide.yml
- include_tasks: redis.yml
EOF

# 10. Update Variables
cat >> ${BASE_DIR}/group_vars/all.yml <<'EOF'

# Security Enhancements
redis_password: "{{ 24 | random_password }}"
backup_passphrase: "{{ 50 | random_password }}"

# Monitoring Configuration
prometheus_scrape_interval: 60s
prometheus_targets:
  - name: mailserver
    port: 11334
EOF

# 11. Final Requirements
echo "python3-psycopg2" >> ${BASE_DIR}/requirements.txt

echo "All missing components implemented successfully!"
echo "Important next steps:"
echo "1. Run 'ansible-vault encrypt group_vars/all.yml' to secure secrets"
echo "2. Review firewall rules in host_nftables.conf.j2"
echo "3. Test backup and restore procedures"
echo "4. Initialize monitoring dashboard in Grafana"
