locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  node_config = {
    for name, node in var.nodes : name => {
      ip         = node.ip
      mac_mgmt   = format("52:54:00:00:01:%02d", tonumber(split(".", node.ip)[3]))
      mac_uplink = format("52:54:00:00:02:%02d", tonumber(split(".", node.ip)[3]))
    }
  }
}
