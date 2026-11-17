resource "libvirt_domain" "node" {
  for_each = local.node_config

  name        = each.key
  type        = "kvm"
  vcpu        = var.node_vcpu
  memory      = var.node_memory_mib
  memory_unit = "MiB"
  running     = true

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [{ dev = "hd" }]
  }

  # Required for nested virtualization (LXD VMs inside MicroCloud)
  cpu = {
    mode = "host-passthrough"
  }

  features = {
    acpi = true
  }

  devices = {
    # Disks are attached by file path rather than pool/volume reference so that
    # virt-aa-helper can add them (and the backing image) to the AppArmor profile.
    disks = [
      {
        source = {
          file = { file = libvirt_volume.os_disk[each.key].path }
        }
        driver = { name = "qemu", type = "qcow2" }
        target = { dev = "vda", bus = "virtio" }
        serial = "${each.key}-os"
      },
      {
        source = {
          file = { file = libvirt_volume.ceph_disk[each.key].path }
        }
        driver = { name = "qemu", type = "qcow2" }
        target = { dev = "vdb", bus = "virtio" }
        serial = "${each.key}-ceph"
      },
      {
        device = "cdrom"
        source = {
          file = { file = libvirt_volume.seed[each.key].path }
        }
        target = { dev = "sda", bus = "sata" }
      },
    ]

    interfaces = [
      {
        mac    = { address = each.value.mac_mgmt }
        model  = { type = "virtio" }
        source = { bridge = { bridge = var.bridge_name } }
      },
      {
        mac    = { address = each.value.mac_uplink }
        model  = { type = "virtio" }
        source = { bridge = { bridge = var.bridge_name } }
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
