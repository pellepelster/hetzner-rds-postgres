output "public_ip" {
  value = hcloud_floating_ip.floating_ip.ip_address
}