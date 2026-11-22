output "nodes" {
  description = "Node management IPs and MAC addresses"
  value = {
    for name, node in local.node_config : name => {
      ip         = node.ip
      ceph_ip    = node.ceph_ip
      fqdn       = "${name}.${var.domain}"
      mac_mgmt   = node.mac_mgmt
      mac_uplink = node.mac_uplink
      mac_ceph   = node.mac_ceph
      ssh        = "ssh ${var.vm_user}@${node.ip}"
    }
  }
}

output "obs" {
  description = "Observability VM"
  value = {
    name = var.obs_node.name
    ip   = var.obs_node.ip
    fqdn = "${var.obs_node.name}.${var.domain}"
    mac  = local.obs_mac
    ssh  = "ssh ${var.vm_user}@${var.obs_node.ip}"
  }
}
