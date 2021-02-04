#!/usr/bin/env bash

# ${ uuid()}

set -o pipefail -o errexit -o nounset

export DEBIAN_FRONTEND=noninteractive

echo "${ssh_identity_ecdsa_key}" | base64 -d > /etc/ssh/ssh_host_ecdsa_key
chmod 600 /etc/ssh/ssh_host_ecdsa_key
echo "${ssh_identity_ecdsa_pub}" | base64 -d > /etc/ssh/ssh_host_ecdsa_key.pub

echo "${ssh_identity_rsa_key}" | base64 -d > /etc/ssh/ssh_host_rsa_key
chmod 600 /etc/ssh/ssh_host_rsa_key.pub
echo "${ssh_identity_rsa_pub}" | base64 -d > /etc/ssh/ssh_host_rsa_key.pub

echo "${ssh_identity_ed25519_key}" | base64 -d > /etc/ssh/ssh_host_ed25519_key
chmod 600 /etc/ssh/ssh_host_ed25519_key.pub
echo "${ssh_identity_ed25519_pub}" | base64 -d > /etc/ssh/ssh_host_ed25519_key.pub

function docker_login {
  echo "${github_token}" | docker login https://docker.pkg.github.com -u ${github_owner} --password-stdin
}

# snippet:terraform_data_volumes_mount
function mount_storage_backup {
    echo "${storage_device_backup} /storage/backup   ext4   defaults  0 0" >> /etc/fstab
    mkdir -p "/storage/backup"
    mount "/storage/backup"

    chown 4000:4000 "/storage/backup"
}

function mount_storage_data {
    echo "${storage_device_data} /storage/data   ext4   defaults  0 0" >> /etc/fstab
    mkdir -p "/storage/data"
    mount "/storage/data"

    chown 4000:4000 "/storage/data"
}
# /snippet:terraform_data_volumes_mount

function configure_public_ip {
    ip addr add ${public_ip} dev eth0
}

function update_system {
    apt-get update

    apt-get \
        -o Dpkg::Options::="--force-confnew" \
        --force-yes \
        -fuy \
        dist-upgrade
}

function install_prerequisites {
  apt-get install --no-install-recommends -qq -y \
    docker.io \
    docker-compose \
    gnupg2 \
    pass \
    ufw \
    uuid
}

function configure_ufw {
  ufw enable
  ufw allow ssh
  ufw allow 5432
}

# snippet:rds_service_backup_systemd_config
function rds_service_backup_systemd_config {
cat <<-EOF
[Unit]
Description=rds instance %i backup
Requires=docker.service
After=docker.service

[Service]
WorkingDirectory=/opt/dockerfiles/%i
ExecStart=/usr/bin/docker-compose exec -T %i /rds/bin/backup.sh

[Install]
WantedBy=multi-user.target
EOF
}
# /snippet:rds_service_backup_systemd_config

# snippet:rds_service_backup_timer_systemd_config
function rds_service_backup_timer_systemd_config {
cat <<-EOF

[Unit]
Description=rds instance %i backup timer

[Timer]
OnCalendar=hourly

[Install]
WantedBy=basic.target
EOF
}
# /snippet:rds_service_backup_timer_systemd_config

# snippet:rds_service_systemd_config
function rds_service_systemd_config {
cat <<-EOF
[Unit]
Description=rds instance %i
Requires=docker.service
After=docker.service

[Service]
Restart=always
TimeoutStartSec=1200

WorkingDirectory=/opt/dockerfiles/%i

ExecStartPre=/usr/bin/docker-compose down -v
ExecStartPre=/usr/bin/docker-compose rm -fv
ExecStartPre=/usr/bin/docker-compose pull

# Compose up
ExecStart=/usr/bin/docker-compose up

# Compose down, remove containers and volumes
ExecStop=/usr/bin/docker-compose down -v

[Install]
WantedBy=multi-user.target
EOF
}
# /snippet:rds_service_systemd_config

# snippet:docker_compose_config
function docker_compose_config {
cat <<-EOF
version: "3"
services:
  ${rds_instance_id}:
    image: docker.pkg.github.com/pellepelster/hetzner-rds-postgres/hetzner-rds-postgres:latest
    environment:
      - "DB_DATABASE=${rds_instance_id}"
      - "DB_PASSWORD=very-secret"
    ports:
      - "5432:5432"
    volumes:
      - "/storage/data:/storage/data"
      - "/storage/backup:/storage/backup"
EOF
}
# /snippet:docker_compose_config

mount_storage_backup
mount_storage_data
configure_public_ip
update_system
install_prerequisites
configure_ufw
docker_login


mkdir -p "/opt/dockerfiles/${rds_instance_id}"
docker_compose_config > "/opt/dockerfiles/${rds_instance_id}/docker-compose.yml"

rds_service_backup_systemd_config > /etc/systemd/system/rds-backup@.service
rds_service_backup_timer_systemd_config > /etc/systemd/system/rds-backup@.timer

rds_service_systemd_config > /etc/systemd/system/rds@.service

systemctl daemon-reload

systemctl enable rds@${rds_instance_id}
systemctl start rds@${rds_instance_id}

systemctl enable rds-backup@${rds_instance_id}.timer
systemctl start rds-backup@${rds_instance_id}.timer
