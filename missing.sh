#!/bin/bash
set -e

BASE_DIR="ansible-mailserver"

# Add monitoring templates
mkdir -p ${BASE_DIR}/roles/mailserver/templates/{prometheus,grafana}

cat > ${BASE_DIR}/roles/mailserver/templates/prometheus/alerts.yml.j2 <<EOF
groups:
- name: mailserver
  rules:
  - alert: HighLoad
    expr: node_load15 > 2
    for: 5m
    labels:
      severity: warning
EOF

cat > ${BASE_DIR}/roles/mailserver/templates/grafana/datasources.yml.j2 <<EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
EOF

# Add AIDE configuration
cat > ${BASE_DIR}/roles/mailserver/templates/aide/aide.conf.j2 <<EOF
/etc p+i+u+g
/bin p+i+u+g
/usr/bin p+i+u+g
EOF

# Add monitoring tasks
cat > ${BASE_DIR}/roles/mailserver/tasks/monitoring.yml <<EOF
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
    - { src: 'grafana/datasources.yml.j2', dest: '/etc/grafana/provisioning/datasources/prometheus.yml' }
  notify: restart monitoring services
EOF

# Update handlers
cat >> ${BASE_DIR}/roles/mailserver/handlers/main.yml <<EOF

- name: restart monitoring services
  systemd:
    name: "{{ item }}"
    state: restarted
  loop:
    - prometheus
    - grafana
EOF

echo "Missing monitoring and integrity components added successfully"
