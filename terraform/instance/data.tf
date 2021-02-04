data "template_file" "user_data" {

  template = file("user_data.sh")

  vars = {
    public_ip = hcloud_floating_ip.floating_ip.ip_address

    github_owner = var.github_owner
    github_token = var.github_token

    # snippet:terraform_user_data_template
    storage_device_data = data.hcloud_volume.data.linux_device
    storage_device_backup = data.hcloud_volume.backup.linux_device
    # /snippet:terraform_user_data_template

    rds_instance_id = var.rds_instance_id

    ssh_identity_ecdsa_key = var.ssh_identity_ecdsa_key
    ssh_identity_ecdsa_pub = var.ssh_identity_ecdsa_pub

    ssh_identity_rsa_key = var.ssh_identity_rsa_key
    ssh_identity_rsa_pub = var.ssh_identity_rsa_pub

    ssh_identity_ed25519_key = var.ssh_identity_ed25519_key
    ssh_identity_ed25519_pub = var.ssh_identity_ed25519_pub
  }
}

# snippet:terraform_data_volumes_loookup
data "hcloud_volume" "data" {
  name = "${var.rds_instance_id}-data"
}

data "hcloud_volume" "backup" {
  name = "${var.rds_instance_id}-backup"
}
# /snippet:terraform_data_volumes_loookup

