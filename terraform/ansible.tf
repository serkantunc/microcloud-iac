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
            ceph_network_cidr = var.ceph_network_cidr
          }
        }
      }
    }
  })
}
