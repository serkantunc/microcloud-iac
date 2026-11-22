provider "libvirt" {
  alias = "obs"
  uri   = var.obs_libvirt_uri
}

locals {
  obs_mac = format("52:54:00:00:04:%02d", tonumber(split(".", var.obs_node.ip)[3]))
}

resource "libvirt_pool" "obs" {
  provider = libvirt.obs

  name = var.obs_pool_name
  type = "dir"

  target = {
    path = var.obs_pool_path
  }

  create = {
    build     = true
    start     = true
    autostart = true
  }
}

resource "libvirt_volume" "obs_base" {
  provider = libvirt.obs

  name = replace(basename(var.ubuntu_image_url), ".img", ".qcow2")
  pool = libvirt_pool.obs.name

  target = {
    format = { type = "qcow2" }
  }

  create = {
    content = {
      url = var.ubuntu_image_url
    }
  }
}

resource "libvirt_volume" "obs_os" {
  provider = libvirt.obs

  name          = "${var.obs_node.name}-os.qcow2"
  pool          = libvirt_pool.obs.name
  capacity      = var.obs_disk_gib
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }

  backing_store = {
    path   = libvirt_volume.obs_base.path
    format = { type = "qcow2" }
  }
}

resource "libvirt_cloudinit_disk" "obs_seed" {
  name = "${var.obs_node.name}-seed"

  meta_data = yamlencode({
    instance-id    = var.obs_node.name
    local-hostname = var.obs_node.name
  })

  user_data = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
    hostname         = var.obs_node.name
    domain           = var.domain
    ip               = var.obs_node.ip
    timezone         = var.timezone
    user             = var.vm_user
    ssh_public_key   = local.ssh_public_key
    console_password = var.vm_console_password
  })

  network_config = templatefile("${path.module}/templates/network-config-single.yaml.tftpl", {
    mac         = local.obs_mac
    ip          = var.obs_node.ip
    prefix      = var.network_prefix
    gateway     = var.gateway
    dns_servers = var.dns_servers
  })
}

resource "libvirt_volume" "obs_seed" {
  provider = libvirt.obs

  name = "${var.obs_node.name}-seed.iso"
  pool = libvirt_pool.obs.name

  create = {
    content = {
      url = libvirt_cloudinit_disk.obs_seed.path
    }
  }

  # The cloud-init ISO is generated under /tmp on the controller and is gone after a
  # reboot. The seed is only read on first boot, so a missing source is not a change.
  lifecycle {
    ignore_changes = [create]
  }
}

resource "libvirt_domain" "obs" {
  provider = libvirt.obs

  name        = var.obs_node.name
  type        = "kvm"
  vcpu        = var.obs_vcpu
  memory      = var.obs_memory_mib
  memory_unit = "MiB"
  running     = true

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [{ dev = "hd" }]
  }

  cpu = {
    mode = "host-passthrough"
  }

  features = {
    acpi = true
  }

  devices = {
    disks = [
      {
        source = {
          file = { file = libvirt_volume.obs_os.path }
        }
        driver = { name = "qemu", type = "qcow2" }
        target = { dev = "vda", bus = "virtio" }
        serial = "${var.obs_node.name}-os"
      },
      {
        device = "cdrom"
        source = {
          file = { file = libvirt_volume.obs_seed.path }
        }
        target = { dev = "sda", bus = "sata" }
      },
    ]

    interfaces = [
      {
        mac    = { address = local.obs_mac }
        model  = { type = "virtio" }
        source = { bridge = { bridge = var.obs_bridge_name } }
      },
    ]

    graphics = [
      {
        vnc = {
          auto_port = true
          listen    = "127.0.0.1"
        }
      },
    ]

    videos = [
      {
        model = { type = "virtio" }
      },
    ]
  }
}
