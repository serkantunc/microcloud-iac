resource "libvirt_cloudinit_disk" "seed" {
  for_each = local.node_config

  name = "${each.key}-seed"

  meta_data = yamlencode({
    instance-id    = each.key
    local-hostname = each.key
  })

  user_data = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
    hostname         = each.key
    domain           = var.domain
    ip               = each.value.ip
    timezone         = var.timezone
    user             = var.vm_user
    ssh_public_key   = local.ssh_public_key
    console_password = var.vm_console_password
  })

  network_config = templatefile("${path.module}/templates/network-config.yaml.tftpl", {
    mac_mgmt    = each.value.mac_mgmt
    mac_uplink  = each.value.mac_uplink
    mac_ceph    = each.value.mac_ceph
    ceph_ip     = each.value.ceph_ip
    ceph_prefix = split("/", var.ceph_network_cidr)[1]
    ip          = each.value.ip
    prefix      = var.network_prefix
    gateway     = var.gateway
    dns_servers = var.dns_servers
  })
}

resource "libvirt_volume" "seed" {
  for_each = local.node_config

  name = "${each.key}-seed.iso"
  pool = libvirt_pool.microcloud.name

  create = {
    content = {
      url = libvirt_cloudinit_disk.seed[each.key].path
    }
  }

  # The cloud-init ISO is generated under /tmp on the controller and is gone after a
  # reboot. The seed is only read on first boot, so a missing source is not a change.
  lifecycle {
    ignore_changes = [create]
  }
}
