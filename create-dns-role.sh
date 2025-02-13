#!/bin/bash
set -e

BASE_DIR="ansible-mailserver"

# Create DNS config role structure
mkdir -p ${BASE_DIR}/roles/dns_config/tasks

# roles/dns_config/tasks/main.yml
cat > ${BASE_DIR}/roles/dns_config/tasks/main.yml <<EOF
---
- name: Create A record
  uri:
    url: "https://api.gandi.net/v5/livedns/domains/{{ domain }}/records/@/A"
    method: PUT
    headers:
      Authorization: "Apikey {{ gandi_api_key }}"
    body:
      rrset_values: ["{{ host_public_ip }}"]
      rrset_ttl: 300
    body_format: json

- name: Create MX record
  uri:
    url: "https://api.gandi.net/v5/livedns/domains/{{ domain }}/records/@/MX"
    method: PUT
    headers:
      Authorization: "Apikey {{ gandi_api_key }}"
    body:
      rrset_values: ["10 {{ domain }}."]
    body_format: json

- name: Create SPF record
  uri:
    url: "https://api.gandi.net/v5/livedns/domains/{{ domain }}/records/@/TXT"
    method: PUT
    headers:
      Authorization: "Apikey {{ gandi_api_key }}"
    body:
      rrset_values: ['"v=spf1 mx -all"']
    body_format: json

- name: Create DKIM record
  uri:
    url: "https://api.gandi.net/v5/livedns/domains/{{ domain }}/records/mail._domainkey/TXT"
    method: PUT
    headers:
      Authorization: "Apikey {{ gandi_api_key }}"
    body:
      rrset_values: ['"v=DKIM1; k=rsa; p={{ dkim_public_key }}"']
    body_format: json

- name: Create DMARC record
  uri:
    url: "https://api.gandi.net/v5/livedns/domains/{{ domain }}/records/_dmarc/TXT"
    method: PUT
    headers:
      Authorization: "Apikey {{ gandi_api_key }}"
    body:
      rrset_values: ['"v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s; rua=mailto:{{ email }}; ruf=mailto:{{ email }};"']
    body_format: json
EOF

# Update requirements.txt
echo -e "ansible>=7.0\njmespath\npasslib" > ${BASE_DIR}/requirements.txt

echo "DNS config role and requirements.txt created successfully"
