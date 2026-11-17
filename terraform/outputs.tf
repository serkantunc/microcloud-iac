output "nodes" {
  description = "Node management IPs and MAC addresses"
  value = {
    for name, node in local.node_config : name => {
      ip         = node.ip
      mac_mgmt   = node.mac_mgmt
      mac_uplink = node.mac_uplink
      ssh        = "ssh ${var.vm_user}@${node.ip}"
    }
  }
}
