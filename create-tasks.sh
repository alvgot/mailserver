#!/bin/bash
set -e

TASKS_DIR="ansible-mailserver/roles/mailserver/tasks"

# Create main.yml
cat > ${TASKS_DIR}/main.yml <<EOF
---
- name: Install base packages
  apt:
    name: ["{{ item }}"]
    state: present
  loop:
    - suricata
    - rkhunter
    - nftables
    - spamassassin
    - fail2ban
    - aide
    - postfix
    - dovecot-core
    - dovecot-imapd
    - roundcube
    - caddy
    - opendkim
    - redis-server
    - unattended-upgrades

- include_tasks: firewall.yml
- include_tasks: postfix.yml
- include_tasks: dovecot.yml
- include_tasks: opendkim.yml
- include_tasks: suricata.yml
- include_tasks: spamassassin.yml
- include_tasks: fail2ban.yml
- include_tasks: aide.yml
- include_tasks: roundcube.yml
- include_tasks: caddy.yml
- include_tasks: rkhunter.yml
- include_tasks: users.yml
- include_tasks: monitoring.yml
- include_tasks: backup.yml
EOF

# Create postfix.yml
cat > ${TASKS_DIR}/postfix.yml <<EOF
---
- name: Configure Postfix main config
  template:
    src: postfix/main.cf.j2
    dest: /etc/postfix/main.cf
  notify: restart postfix

- name: Configure Postfix master config
  template:
    src: postfix/master.cf.j2
    dest: /etc/postfix/master.cf
  notify: restart postfix

- name: Create postfix SASL directory
  file:
    path: /etc/postfix/sasl
    state: directory
    mode: 0750

- name: Configure SASL authentication
  copy:
    content: "mech_list: plain login"
    dest: /etc/postfix/sasl/smtpd.conf

- name: Generate TLS certificates
  command: |
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -subj "/CN={{ domain }}" \
    -keyout /etc/ssl/private/postfix.key \
    -out /etc/ssl/certs/postfix.crt
  args:
    creates: /etc/ssl/certs/postfix.crt
EOF

# Create dovecot.yml
cat > ${TASKS_DIR}/dovecot.yml <<EOF
---
- name: Configure Dovecot
  template:
    src: dovecot/dovecot.conf.j2
    dest: /etc/dovecot/dovecot.conf
  notify: restart dovecot

- name: Configure SSL settings
  template:
    src: dovecot/10-ssl.conf.j2
    dest: /etc/dovecot/conf.d/10-ssl.conf
  notify: restart dovecot

- name: Configure mail location
  template:
    src: dovecot/10-mail.conf.j2
    dest: /etc/dovecot/conf.d/10-mail.conf
  notify: restart dovecot

- name: Create vmail user
  user:
    name: vmail
    uid: 5000
    group: vmail
    shell: /usr/sbin/nologin
    system: yes
EOF

# Create opendkim.yml
cat > ${TASKS_DIR}/opendkim.yml <<EOF
---
- name: Install OpenDKIM
  apt:
    name: opendkim
    state: present

- name: Create DKIM directory structure
  file:
    path: "/etc/opendkim/keys/{{ domain }}"
    state: directory
    owner: opendkim
    group: opendkim
    mode: 0700

- name: Generate DKIM key pair
  command: >
    opendkim-genkey -b 2048 -D /etc/opendkim/keys/{{ domain }}/
    -d {{ domain }} -s mail -v
  args:
    creates: /etc/opendkim/keys/{{ domain }}/mail.private

- name: Set DKIM key permissions
  file:
    path: "/etc/opendkim/keys/{{ domain }}/mail.private"
    mode: 0600
    owner: opendkim
    group: opendkim

- name: Configure OpenDKIM
  template:
    src: opendkim/opendkim.conf.j2
    dest: /etc/opendkim.conf
  notify: restart opendkim
EOF

# Create suricata.yml
cat > ${TASKS_DIR}/suricata.yml <<EOF
---
- name: Update Suricata rules
  command: suricata-update
  when: suricata_rule_update

- name: Configure Suricata
  template:
    src: suricata/suricata.yaml.j2
    dest: /etc/suricata/suricata.yaml
  notify: restart suricata

- name: Enable Suricata service
  systemd:
    name: suricata
    enabled: yes
    state: started
EOF

# Create spamassassin.yml
cat > ${TASKS_DIR}/spamassassin.yml <<EOF
---
- name: Update SpamAssassin rules
  command: sa-update

- name: Configure SpamAssassin
  template:
    src: spamassassin/local.cf.j2
    dest: /etc/spamassassin/local.cf
  notify: restart spamassassin

- name: Enable SpamAssassin service
  systemd:
    name: spamassassin
    enabled: yes
    state: started
EOF

# Create fail2ban.yml
cat > ${TASKS_DIR}/fail2ban.yml <<EOF
---
- name: Configure Fail2Ban
  template:
    src: fail2ban/jail.local.j2
    dest: /etc/fail2ban/jail.local
  notify: restart fail2ban

- name: Create Postfix filter
  template:
    src: fail2ban/filter-postfix.conf.j2
    dest: /etc/fail2ban/filter.d/postfix.conf
  notify: restart fail2ban

- name: Enable Fail2Ban service
  systemd:
    name: fail2ban
    enabled: yes
    state: started
EOF

# Create aide.yml
cat > ${TASKS_DIR}/aide.yml <<EOF
---
- name: Configure AIDE
  template:
    src: aide/aide.conf.j2
    dest: /etc/aide/aide.conf

- name: Initialize AIDE database
  command: aideinit -y

- name: Schedule daily AIDE checks
  cron:
    name: "Daily AIDE check"
    job: "/usr/bin/aide --check"
    user: root
    hour: 4
    minute: 30
EOF

# Create roundcube.yml
cat > ${TASKS_DIR}/roundcube.yml <<EOF
---
- name: Configure Roundcube
  template:
    src: roundcube/config.inc.php.j2
    dest: /etc/roundcube/config.inc.php

- name: Initialize Roundcube database
  mysql_db:
    name: "{{ roundcube_db_name }}"
    state: import
    target: /usr/share/roundcube/SQL/mysql.initial.sql

- name: Set Roundcube permissions
  file:
    path: /var/lib/roundcube
    owner: www-data
    group: www-data
    recurse: yes
EOF

# Create caddy.yml
cat > ${TASKS_DIR}/caddy.yml <<EOF
---
- name: Configure Caddy
  template:
    src: caddy/Caddyfile.j2
    dest: /etc/caddy/Caddyfile
  notify: reload caddy

- name: Enable Caddy service
  systemd:
    name: caddy
    enabled: yes
    state: started
EOF

# Create rkhunter.yml
cat > ${TASKS_DIR}/rkhunter.yml <<EOF
---
- name: Configure RKHunter
  template:
    src: rkhunter/rkhunter.conf.j2
    dest: /etc/rkhunter.conf

- name: Update RKHunter database
  command: rkhunter --update

- name: Schedule daily RKHunter scans
  cron:
    name: "Daily RKHunter scan"
    job: "/usr/bin/rkhunter --cronjob --report-warnings-only"
    user: root
    hour: 3
    minute: 0
EOF

# Create users.yml
cat > ${TASKS_DIR}/users.yml <<EOF
---
- name: Create mail users
  user:
    name: "{{ item.name }}"
    password: "{{ item.password | password_hash('sha512') }}"
    groups: vmail
    shell: /usr/sbin/nologin
  loop: "{{ mail_users }}"
  no_log: true

- name: Create mail directories
  file:
    path: "/var/mail/vhosts/{{ domain }}/{{ item.name }}"
    state: directory
    owner: "{{ item.name }}"
    group: vmail
    mode: 0700
  loop: "{{ mail_users }}"
EOF

# Create monitoring.yml
cat > ${TASKS_DIR}/monitoring.yml <<EOF
---
- name: Install Prometheus
  apt:
    name: prometheus
    state: present

- name: Configure Prometheus
  template:
    src: prometheus/prometheus.yml.j2
    dest: /etc/prometheus/prometheus.yml
  notify: restart prometheus

- name: Install Node Exporter
  apt:
    name: prometheus-node-exporter
    state: present
EOF

# Create backup.yml
cat > ${TASKS_DIR}/backup.yml <<EOF
---
- name: Install BorgBackup
  apt:
    name: borgbackup
    state: present

- name: Configure backup script
  template:
    src: backup.sh.j2
    dest: /usr/local/bin/mailserver-backup
    mode: 0755

- name: Create backup cron job
  cron:
    name: "Daily Mailserver Backup"
    job: "/usr/local/bin/mailserver-backup > /var/log/backup.log 2>&1"
    user: root
    hour: 2
    minute: 30
EOF

# Create firewall.yml
cat > ${TASKS_DIR}/firewall.yml <<EOF
---
- name: Configure nftables
  template:
    src: nftables/container_nftables.conf.j2
    dest: /etc/nftables.conf
  notify: restart nftables

- name: Enable nftables service
  systemd:
    name: nftables
    enabled: yes
    state: started
EOF

echo "All task files created successfully in ${TASKS_DIR}"
