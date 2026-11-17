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
            }
          }
          vars = {
            ansible_user = var.vm_user
          }
        }
      }
    }
  })
}
