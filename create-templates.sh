#!/bin/bash
set -e

TEMPLATES_DIR="ansible-mailserver/roles/mailserver/templates"

# Create Postfix templates
mkdir -p ${TEMPLATES_DIR}/postfix
cat > ${TEMPLATES_DIR}/postfix/main.cf.j2 <<EOF
# Postfix main configuration
smtpd_banner = \$myhostname ESMTP
biff = no
append_dot_mydomain = no

# TLS parameters
smtpd_tls_cert_file=/etc/ssl/certs/postfix.crt
smtpd_tls_key_file=/etc/ssl/private/postfix.key
smtpd_tls_security_level=may

# Authentication
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes

# Network settings
myhostname = mail.{{ domain }}
mydomain = {{ domain }}
myorigin = \$mydomain
inet_interfaces = all
mydestination = \$myhostname, \$mydomain, localhost
EOF

cat > ${TEMPLATES_DIR}/postfix/master.cf.j2 <<EOF
# Postfix master process configuration
smtp      inet  n       -       y       -       -       smtpd
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
pickup    unix  n       -       y       60      1       pickup
cleanup   unix  n       -       y       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
tlsmgr    unix  -       -       y       1000?   1       tlsmgr
EOF

# Create Dovecot templates
mkdir -p ${TEMPLATES_DIR}/dovecot
cat > ${TEMPLATES_DIR}/dovecot/dovecot.conf.j2 <<EOF
# Dovecot core configuration
protocols = imap
ssl = required
ssl_cert = </etc/ssl/certs/postfix.crt
ssl_key = </etc/ssl/private/postfix.key
auth_mechanisms = plain login
EOF

cat > ${TEMPLATES_DIR}/dovecot/10-auth.conf.j2 <<EOF
# Authentication configuration
disable_plaintext_auth = no
auth_username_format = %n
passdb {
  driver = pam
}
userdb {
  driver = passwd
}
EOF

cat > ${TEMPLATES_DIR}/dovecot/10-ssl.conf.j2 <<EOF
# SSL configuration
ssl = required
ssl_min_protocol = TLSv1.2
ssl_cipher_list = EECDH+AESGCM:EDH+AESGCM
ssl_prefer_server_ciphers = yes
EOF

cat > ${TEMPLATES_DIR}/dovecot/10-mail.conf.j2 <<EOF
# Mailbox locations
mail_location = maildir:/var/mail/vhosts/%d/%n
mail_privileged_group = mail
EOF

# Create OpenDKIM templates
mkdir -p ${TEMPLATES_DIR}/opendkim
cat > ${TEMPLATES_DIR}/opendkim/opendkim.conf.j2 <<EOF
# OpenDKIM configuration
Domain                  {{ domain }}
KeyFile                 /etc/opendkim/keys/{{ domain }}/mail.private
Selector                mail
Socket                  inet:8891@localhost
UserID                  opendkim:opendkim
Canonicalization        relaxed/simple
Mode                    sv
SubDomains              yes
EOF

cat > ${TEMPLATES_DIR}/opendkim/keytable.j2 <<EOF
mail._domainkey.{{ domain }} {{ domain }}:mail:/etc/opendkim/keys/{{ domain }}/mail.private
EOF

cat > ${TEMPLATES_DIR}/opendkim/signingtable.j2 <<EOF
*@{{ domain }} mail._domainkey.{{ domain }}
EOF

# Create Suricata template
mkdir -p ${TEMPLATES_DIR}/suricata
cat > ${TEMPLATES_DIR}/suricata/suricata.yaml.j2 <<EOF
%YAML 1.1
---
vars:
  address-groups:
    HOME_NET: "[{{ container_ip }}]"
    EXTERNAL_NET: "any"
default-rule-path: /var/lib/suricata/rules
rule-files:
  - suricata.rules
EOF

# Create SpamAssassin templates
mkdir -p ${TEMPLATES_DIR}/spamassassin
cat > ${TEMPLATES_DIR}/spamassassin/local.cf.j2 <<EOF
required_score 5.0
report_safe 0
rewrite_header Subject *** SPAM ***
EOF

cat > ${TEMPLATES_DIR}/spamassassin/v310.pre.j2 <<EOF
loadplugin Mail::SpamAssassin::Plugin::Rule2XSBody
loadplugin Mail::SpamAssassin::Plugin::AWL
EOF

# Create Fail2Ban templates
mkdir -p ${TEMPLATES_DIR}/fail2ban
cat > ${TEMPLATES_DIR}/fail2ban/jail.local.j2 <<EOF
[postfix]
enabled = true
maxretry = {{ fail2ban_maxretry }}
bantime = {{ fail2ban_bantime }}
EOF

cat > ${TEMPLATES_DIR}/fail2ban/filter-postfix.conf.j2 <<EOF
[Definition]
failregex = reject: RCPT from \S+\[<HOST>\]: 550 5.1.1
ignoreregex =
EOF

# Create AIDE template
mkdir -p ${TEMPLATES_DIR}/aide
cat > ${TEMPLATES_DIR}/aide/aide.conf.j2 <<EOF
# AIDE configuration
/etc p+i+u+g
/bin p+i+u+g
/usr/bin p+i+u+g
/root/\..* p+i+u+g
EOF

# Create Roundcube templates
mkdir -p ${TEMPLATES_DIR}/roundcube/plugins/password
cat > ${TEMPLATES_DIR}/roundcube/config.inc.php.j2 <<EOF
<?php
\$config = array(
    'db_dsnw' => 'pgsql://{{ roundcube_db_user }}:{{ roundcube_db_password }}@localhost/{{ roundcube_db_name }}',
    'default_host' => 'ssl://localhost',
    'smtp_server' => 'tls://localhost',
    'product_name' => '{{ domain }} Webmail',
    'plugins' => array('password'),
);
EOF

# Create Caddy template
mkdir -p ${TEMPLATES_DIR}/caddy
cat > ${TEMPLATES_DIR}/caddy/Caddyfile.j2 <<EOF
mail.{{ domain }} {
    tls {{ email }}
    reverse_proxy /roundcube/* 127.0.0.1:80
}
EOF

# Create nftables template
mkdir -p ${TEMPLATES_DIR}/nftables
cat > ${TEMPLATES_DIR}/nftables/container_nftables.conf.j2 <<EOF
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        ct state established,related accept
        tcp dport { 25, 80, 443, 465, 587, 993, 995 } accept
    }
}
EOF

# Create rkhunter template
mkdir -p ${TEMPLATES_DIR}/rkhunter
cat > ${TEMPLATES_DIR}/rkhunter/rkhunter.conf.j2 <<EOF
UPDATE_MIRRORS=1
MIRRORS_MODE=0
WEB_CMD=""
EMAIL_ADDR="{{ email }}"
EOF

# Create Prometheus templates
mkdir -p ${TEMPLATES_DIR}/prometheus
cat > ${TEMPLATES_DIR}/prometheus/prometheus.yml.j2 <<EOF
global:
  scrape_interval: 60s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
EOF

# Create Grafana template
mkdir -p ${TEMPLATES_DIR}/grafana
cat > ${TEMPLATES_DIR}/grafana/datasources.yml.j2 <<EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
EOF

echo "All template files created successfully in ${TEMPLATES_DIR}"
