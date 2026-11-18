resource "libvirt_pool" "microcloud" {
  name = var.pool_name
  type = "dir"

  target = {
    path = var.pool_path
  }

  create = {
    build     = true
    start     = true
    autostart = true
  }
}

resource "libvirt_volume" "ubuntu_base" {
  name = replace(basename(var.ubuntu_image_url), ".img", ".qcow2")
  pool = libvirt_pool.microcloud.name

  target = {
    format = { type = "qcow2" }
  }

  create = {
    content = {
      url = var.ubuntu_image_url
    }
  }
}

resource "libvirt_volume" "os_disk" {
  for_each = var.nodes

  name          = "${each.key}-os.qcow2"
  pool          = libvirt_pool.microcloud.name
  capacity      = var.os_disk_gib
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }

  backing_store = {
    path   = libvirt_volume.ubuntu_base.path
    format = { type = "qcow2" }
  }
}

resource "libvirt_volume" "ceph_disk" {
  for_each = var.nodes

  name          = "${each.key}-ceph.qcow2"
  pool          = libvirt_pool.microcloud.name
  capacity      = var.ceph_disk_gib
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }
}

resource "libvirt_volume" "local_disk" {
  for_each = var.nodes

  name          = "${each.key}-local.qcow2"
  pool          = libvirt_pool.microcloud.name
  capacity      = var.local_disk_gib
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }
}
