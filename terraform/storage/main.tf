terraform {
  required_providers {
    hcloud = {
      source = "terraform-providers/hcloud"
      version = "1.23.0"
    }
  }

  required_version = ">= 0.13"
}

provider "hcloud" {
  token = var.cloud_api_token
}

# snippet:terraform_data_volumes
resource "hcloud_volume" "data" {
  name = "${var.rds_instance_id}-data"
  size = 64
  format = "ext4"
  location = var.location
}

resource "hcloud_volume" "backup" {
  name = "${var.rds_instance_id}-backup"
  size = 64
  format = "ext4"
  location = var.location
}
# /snippet:terraform_data_volumes
