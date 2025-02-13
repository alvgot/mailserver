#!/bin/bash
set -e

BASE_DIR="ansible-mailserver"

# Create directory structure
mkdir -p ${BASE_DIR}/group_vars
mkdir -p ${BASE_DIR}/roles/host_setup/{tasks,templates}

# ansible.cfg
cat > ${BASE_DIR}/ansible.cfg <<EOF
[defaults]
inventory = ./inventory
roles_path = ./roles
gathering = explicit
host_key_checking = False
EOF

# inventory
cat > ${BASE_DIR}/inventory <<EOF
[host]
mailhost ansible_connection=local

[container]
mailcontainer ansible_host=10.0.0.2 ansible_user=root
EOF

# playbook.yml
cat > ${BASE_DIR}/playbook.yml <<EOF
---
- hosts: host
  roles:
    - host_setup

- hosts: container
  roles:
    - mailserver
EOF

# group_vars/all.yml
cat > ${BASE_DIR}/group_vars/all.yml <<EOF
---
domain: example.com
email: admin@example.com
container_ip: 10.0.0.2
gandi_api_key: your_api_key_here
EOF

# roles/host_setup/tasks/main.yml
cat > ${BASE_DIR}/roles/host_setup/tasks/main.yml <<EOF
---
- name: Add Incus repository
  apt_repository:
    repo: deb [arch=amd64] https://ubuntu.com/incus/static/stable/debian/ bookworm incus
    state: present

- name: Install Incus
  apt:
    name: incus
    state: present
    update_cache: yes

- name: Initialize Incus with dir backend
  command: incus init --storage-backend dir --auto

- name: Launch Debian 12 container
  command: incus launch images:debian/12 mailcontainer -c security.nesting=true

- name: Configure container networking
  command: incus config device set mailcontainer eth0 ipv4.address {{ container_ip }}

- name: Install nftables on host
  apt:
    name: nftables
    state: present

- name: Configure host firewall
  template:
    src: host_nftables.conf.j2
    dest: /etc/nftables.conf
  notify: restart nftables

- name: Enable IP forwarding
  sysctl:
    name: net.ipv4.ip_forward
    value: '1'
    state: present
EOF

# roles/host_setup/templates/host_nftables.conf.j2
cat > ${BASE_DIR}/roles/host_setup/templates/host_nftables.conf.j2 <<EOF
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0;
        policy drop;
        iif lo accept
        ct state established,related accept
        icmp type echo-request accept
        tcp dport {22} accept
    }
    
    chain forward {
        type filter hook forward priority 0;
        policy drop;
        ct state established,related accept
        iif eth0 oif incusbr0 accept
    }
    
    chain output {
        type filter hook output priority 0;
        policy accept;
    }
}

table ip nat {
    chain prerouting {
        type nat hook prerouting priority 0;
        tcp dport {25,143,465,587,993,80,443} dnat to {{ container_ip }}
    }
    
    chain postrouting {
        type nat hook postrouting priority 100;
        oifname "eth0" masquerade
    }
}
EOF

echo "All files created successfully in ${BASE_DIR}/ directory structure"
