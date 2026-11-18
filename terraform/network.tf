# No forward mode and no IP: an isolated bridge that only the nodes are attached to.
resource "libvirt_network" "ceph" {
  name      = "mc-ceph"
  autostart = true

  bridge = {
    name = "virbr-mcceph"
  }
}
