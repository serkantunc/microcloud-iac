variable "libvirt_uri" {
  description = "libvirt connection URI"
  type        = string
  default     = "qemu:///system"
}

variable "nodes" {
  description = "MicroCloud cluster members and their management IPs"
  type = map(object({
    ip = string
  }))
  default = {
    micro1 = { ip = "192.168.1.61" }
    micro2 = { ip = "192.168.1.62" }
    micro3 = { ip = "192.168.1.63" }
  }

  validation {
    condition     = alltrue([for n in values(var.nodes) : tonumber(split(".", n.ip)[3]) < 100])
    error_message = "The last octet of each node IP must be below 100; it is reused in the node MAC addresses."
  }
}

variable "node_vcpu" {
  type    = number
  default = 6
}

variable "node_memory_mib" {
  type    = number
  default = 12288
}

variable "os_disk_gib" {
  type    = number
  default = 40
}

variable "ceph_disk_gib" {
  type    = number
  default = 60
}

variable "pool_name" {
  type    = string
  default = "microcloud"
}

variable "pool_path" {
  type    = string
  default = "/var/lib/libvirt/microcloud"
}

variable "ubuntu_image_url" {
  description = "Ubuntu 26.04 LTS (Resolute) cloud image"
  type        = string
  default     = "https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img"
}

variable "bridge_name" {
  description = "Host bridge the VMs attach to"
  type        = string
  default     = "br-mc"
}

variable "network_prefix" {
  type    = number
  default = 24
}

variable "gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "dns_servers" {
  type    = list(string)
  default = ["1.1.1.1", "192.168.1.1"]
}

variable "vm_user" {
  type    = string
  default = "ubuntu"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "vm_console_password" {
  description = "Password for serial console login only. Empty disables password login."
  type        = string
  default     = ""
  sensitive   = true
}

variable "timezone" {
  type    = string
  default = "Etc/UTC"
}
