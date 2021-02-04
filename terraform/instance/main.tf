terraform {
  required_providers {

    hcloud = {
      source = "hetznercloud/hcloud"
      version = "1.23.0"
    }

    template = {
      source = "hashicorp/template"
    }
  }

  required_version = ">= 0.13"
}

provider "hcloud" {
  token = var.cloud_api_token
}

resource "hcloud_server" "instance" {
  name = var.rds_instance_id
  image = "debian-10"
  server_type = "cx11"
  location = var.location
  user_data = data.template_file.user_data.rendered
  ssh_keys = [
    hcloud_ssh_key.id_rsa.id]
}

resource "hcloud_floating_ip_assignment" "ip_assignment" {
  floating_ip_id = hcloud_floating_ip.floating_ip.id
  server_id = hcloud_server.instance.id
}

resource "hcloud_floating_ip" "floating_ip" {
  name = "${var.rds_instance_id}"
  type = "ipv4"
  home_location = var.location
}

resource "hcloud_ssh_key" "id_rsa" {
  name = "id_rsa"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "hcloud_volume_attachment" "data" {
  volume_id = data.hcloud_volume.data.id
  server_id = hcloud_server.instance.id
}

resource "hcloud_volume_attachment" "backup" {
  volume_id = data.hcloud_volume.backup.id
  server_id = hcloud_server.instance.id
}
