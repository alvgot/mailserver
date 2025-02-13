#!/bin/bash
set -e

BASE_DIR="ansible-mailserver"

# Create missing directories
mkdir -p ${BASE_DIR}/roles/mailserver/{templates/{prometheus,grafana,aide,redis,logrotate},tasks}

# 1. Monitoring Stack Implementation
cat > ${BASE_DIR}/roles/mailserver/templates/prometheus/alerts.yml.j2 <<EOF
groups:
- name: mailserver
  rules:
  - alert: HighLoad
    expr: node_load15 > 2
    for: 5m
    labels:
      severity: warning
  - alert: ServiceDown
    expr: up{job="mailserver"} == 0
    for: 1m
    labels:
      severity: critical
EOF

cat > ${BASE_DIR}/roles/mailserver/templates/grafana/datasources.yml.j2 <<EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF

# 2. File Integrity Monitoring
cat > ${BASE_DIR}/roles/mailserver/templates/aide/aide.conf.j2 <<EOF
@@define DBDIR /var/lib/aide
@@define LOGDIR /var/log/aide

# Basic system integrity checks
/etc p+i+u+g+sha512
/bin p+i+u+g+sha512
/usr/bin p+i+u+g+sha512
/var/mail p+i+u+g+sha512
EOF

# 3. Redis Configuration
cat > ${BASE_DIR}/roles/mailserver/templates/redis/redis.conf.j2 <<EOF
bind 127.0.0.1
protected-mode yes
requirepass {{ redis_password }}
maxmemory 512mb
maxmemory-policy allkeys-lru
EOF

# 4. Webmail Enhancements
mkdir -p ${BASE_DIR}/roles/mailserver/templates/roundcube/plugins/password
cat > ${BASE_DIR}/roles/mailserver/templates/roundcube/plugins/password/config.inc.php.j2 <<EOF
<?php
\$config['password_driver'] = 'sql';
\$config['password_confirm_current'] = true;
\$config['password_minimum_length'] = 12;
\$config['password_require_nonalpha'] = true;
\$config['password_db_dsn'] = 'pgsql://{{ postfixadmin_db_user }}:{{ postfixadmin_db_password }}@localhost/{{ postfixadmin_db_name }}';
EOF

# 5. Security Policies
cat > ${BASE_DIR}/roles/mailserver/templates/postfix/spf_policy.j2 <<EOF
check_policy_service unix:private/policy-spf
EOF

# 6. Automatic Updates
cat > ${BASE_DIR}/roles/mailserver/templates/auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
Unattended-Upgrade::Origins-Pattern {
    "o=Debian,a=stable";
};
EOF

# 7. Log Rotation
cat > ${BASE_DIR}/roles/mailserver/templates/logrotate/mailserver <<EOF
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
EOF

# 8. Certificate Auto-Renewal
cat > ${BASE_DIR}/roles/mailserver/templates/caddy-renewal.cron.j2 <<EOF
0 3 * * * /usr/bin/caddy reload --config /etc/caddy/Caddyfile
EOF

# Add new task files
cat > ${BASE_DIR}/roles/mailserver/tasks/monitoring.yml <<EOF
---
- name: Install monitoring stack
  apt:
    name: ["prometheus", "grafana", "prometheus-node-exporter"]
    state: present

- name: Deploy Prometheus config
  template:
    src: prometheus/prometheus.yml.j2
    dest: /etc/prometheus/prometheus.yml
  notify: restart prometheus

- name: Deploy Grafana config
  template:
    src: grafana/datasources.yml.j2
    dest: /etc/grafana/provisioning/datasources/prometheus.yml
  notify: restart grafana

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

cat > ${BASE_DIR}/roles/mailserver/tasks/aide.yml <<EOF
---
- name: Install AIDE
  apt:
    name: aide
    state: present

- name: Configure AIDE
  template:
    src: aide/aide.conf.j2
    dest: /etc/aide/aide.conf

- name: Initialize AIDE database
  command: aideinit -y -f
  args:
    creates: /var/lib/aide/aide.db

- name: Schedule daily AIDE checks
  cron:
    name: "Daily AIDE scan"
    job: "/usr/bin/aide --check"
    user: root
    hour: 5
    minute: 0
EOF

cat > ${BASE_DIR}/roles/mailserver/tasks/redis.yml <<EOF
---
- name: Install Redis
  apt:
    name: redis-server
    state: present

- name: Configure Redis
  template:
    src: redis/redis.conf.j2
    dest: /etc/redis/redis.conf
  notify: restart redis

- name: Enable Redis
  systemd:
    name: redis-server
    enabled: yes
    state: restarted
EOF

# Update handlers
cat >> ${BASE_DIR}/roles/mailserver/handlers/main.yml <<EOF

- name: restart prometheus
  systemd:
    name: prometheus
    state: restarted

- name: restart grafana
  systemd:
    name: grafana
    state: restarted

- name: restart redis
  systemd:
    name: redis-server
    state: restarted
EOF

# Update main tasks file
cat >> ${BASE_DIR}/roles/mailserver/tasks/main.yml <<EOF
- include_tasks: monitoring.yml
- include_tasks: redis.yml
EOF

# Update group_vars
cat >> ${BASE_DIR}/group_vars/all.yml <<EOF

# Security Enhancements
redis_password: "{{ 20 | random_password }}"
auto_updates: true
log_retention_days: 30

# Monitoring Configuration
prometheus_scrape_interval: 60s
EOF

# Update requirements.txt
echo "python3-psycopg2" >> ${BASE_DIR}/requirements.txt

echo "All missing components added successfully!"
echo "Important next steps:"
echo "1. Update group_vars/all.yml with Redis password and monitoring settings"
echo "2. Review security templates for compliance with your organization's policies"
echo "3. Test certificate renewal process"
echo "4. Initialize monitoring stack with Grafana dashboards"
