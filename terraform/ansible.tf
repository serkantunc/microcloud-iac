locals {
  mgmt_network_cidr = "${cidrhost("${var.gateway}/${var.network_prefix}", 0)}/${var.network_prefix}"
}

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.yml"
  file_permission = "0644"

  content = yamlencode({
    all = {
      children = {
        microcloud = {
          hosts = {
            for name, node in local.node_config : name => {
              ansible_host = node.ip
              ceph_ip      = node.ceph_ip
            }
          }
          vars = {
            ansible_user      = var.vm_user
            node_domain       = var.domain
            mgmt_network_cidr = local.mgmt_network_cidr
            ceph_network_cidr = var.ceph_network_cidr
            ovn_ipv4_gateway  = "${var.gateway}/${var.network_prefix}"
            ovn_ipv4_range    = var.ovn_ipv4_range
            ovn_dns_servers   = join(",", var.dns_servers)
          }
        }
        observability = {
          hosts = {
            (var.obs_node.name) = {
              ansible_host = var.obs_node.ip
            }
          }
          vars = {
            ansible_user  = var.vm_user
            node_domain   = var.domain
            metallb_range = var.metallb_range
          }
        }
      }
    }
  })
}
