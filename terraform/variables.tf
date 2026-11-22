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

  validation {
    condition     = length(distinct([for n in values(var.nodes) : n.ip])) == length(var.nodes)
    error_message = "Node IPs must be unique; MAC addresses are derived from them."
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

variable "local_disk_gib" {
  type    = number
  default = 30
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

variable "ceph_network_cidr" {
  description = "Isolated network for Ceph replication and heartbeat traffic"
  type        = string
  default     = "10.10.10.0/24"
}

variable "domain" {
  description = "DNS domain for node FQDNs"
  type        = string
  default     = "home.arpa"
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

variable "ovn_ipv4_range" {
  description = "Addresses on the uplink network that LXD assigns to OVN network routers; keep clear of metallb_range"
  type        = string
  default     = "192.168.1.70-192.168.1.79"
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

variable "obs_libvirt_uri" {
  description = "libvirt connection URI for the observability host"
  type        = string
  default     = "qemu:///system"
}

variable "obs_node" {
  description = "Observability VM: Juju controller, MicroK8s, COS Lite and Cluster Manager"
  type = object({
    name = string
    ip   = string
  })
  default = {
    name = "obs1"
    ip   = "192.168.1.69"
  }

  validation {
    condition     = tonumber(split(".", var.obs_node.ip)[3]) < 100
    error_message = "The last octet of the observability VM IP must be below 100; it is reused in its MAC address."
  }
}

variable "obs_vcpu" {
  type    = number
  default = 4
}

variable "obs_memory_mib" {
  type    = number
  default = 14336
}

variable "obs_disk_gib" {
  type    = number
  default = 100
}

variable "obs_bridge_name" {
  description = "Bridge on the observability host that connects the VM to the LAN"
  type        = string
  default     = "br-mc"
}

variable "obs_pool_name" {
  type    = string
  default = "observability"
}

variable "obs_pool_path" {
  type    = string
  default = "/var/lib/libvirt/observability"
}

variable "metallb_range" {
  description = "LAN addresses MetalLB hands out to LoadBalancer services on the observability VM"
  type        = string
  default     = "192.168.1.96-192.168.1.99"
}
