# microcloud-iac

Infrastructure-as-Code for a **3-node Canonical MicroCloud** lab on KVM/libvirt,
with **MicroK8s** planned as a workload on top.

Target stack (MicroCloud 3 LTS line): MicroCloud 3.4, LXD 6, MicroCeph Tentacle and
MicroOVN 26.03 on Ubuntu 26.04 LTS.

- **Terraform** (libvirt provider 0.9.x) provisions storage, cloud-init seeds and VMs
- **Ansible** *(Phase 2)* installs and initialises MicroCloud (LXD + MicroCeph + MicroOVN)
- **Validation** *(Phase 3)* checks the cluster after deployment
- *(planned)* an **AI agent** that runs the deployment and interprets failures

## Architecture

```
KVM host
└─ br-mc (Linux bridge) ── LAN 192.168.1.0/24
   ├─ micro1  mgmt: 192.168.1.61   uplink: no IP   disks: vda (OS), vdb (Ceph)
   ├─ micro2  mgmt: 192.168.1.62   uplink: no IP   disks: vda (OS), vdb (Ceph)
   └─ micro3  mgmt: 192.168.1.63   uplink: no IP   disks: vda (OS), vdb (Ceph)
```

| Component | Details |
|-----------|---------|
| OS | Ubuntu 26.04 LTS cloud image, shared as a read-only backing file (copy-on-write per node) |
| `mgmt` NIC | Static IP; management, cluster and Ceph traffic |
| `uplink` NIC | Up with no address; reserved for the MicroOVN uplink network |
| Ceph disk | Empty disk per node, exposed as `/dev/disk/by-id/virtio-<node>-ceph` |

Interfaces are matched by MAC address and renamed by netplan, so their names do not
depend on PCI slot ordering. MAC addresses are derived from the node IP
(`52:54:00:00:01:61` for `mgmt` on `.61`).

## Requirements

- KVM host with libvirt (tested with libvirt 12 / QEMU 10.2 on Ubuntu 26.04)
- Nested virtualization enabled (`/sys/module/kvm_intel/parameters/nested` = `Y`)
- Terraform >= 1.6, `xorriso`
- A Linux bridge connected to your LAN (default name `br-mc`)
- An SSH key pair; the public key is injected into every node
- Free static IPs outside your DHCP range (3 for nodes, plus a range for OVN uplink)

## Quick start

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit terraform.tfvars for your network

terraform -chdir=terraform init
terraform -chdir=terraform plan
terraform -chdir=terraform apply

ssh ubuntu@192.168.1.61
```

`terraform output nodes` prints the IP, MAC addresses and SSH command for each node.

## Configuration

All settings are variables in `terraform/variables.tf`. Override them in
`terraform/terraform.tfvars` (not committed). Common ones:

| Variable | Default |
|----------|---------|
| `nodes` | `micro1..3` on `192.168.1.61..63` |
| `node_vcpu` / `node_memory_mib` | `6` / `12288` |
| `os_disk_gib` / `ceph_disk_gib` | `40` / `60` |
| `bridge_name` | `br-mc` |
| `gateway` / `dns_servers` | `192.168.1.1` / `["1.1.1.1", "192.168.1.1"]` |
| `ssh_public_key_path` | `~/.ssh/id_rsa.pub` |
| `vm_console_password` | empty (console password login disabled) |

SSH password authentication is always disabled. `vm_console_password` only enables
login on the VNC console, as a fallback when networking is broken.

## High availability: what this lab does and does not show

All three nodes run on one physical host, so this lab provides **node-level HA**
(stop one VM: dqlite keeps quorum, Ceph runs degraded, workloads keep running),
**not host-level HA**. A host failure takes down the whole cluster.

## Known issues

**AppArmor denies access to the backing image.**
When disks are attached with `source = { volume = { pool, volume } }`, libvirt's
`virt-aa-helper` does not add them to the per-VM AppArmor profile and QEMU fails
with `Permission denied` on the base image. Disks are therefore attached by file
path (`source = { file = { file = ... } }`). Check with
`sudo dmesg | grep 'apparmor="DENIED"'` if you see this error.

**USB Ethernet adapters as bridge ports.**
An ASIX AX88179 adapter bound to `cdc_ncm` did not pass traffic for VM MAC
addresses at first; re-enumerating the device restored it, while the vendor driver
(`ax88179_178a`) failed to establish a link. If VMs can reach each other but not
the LAN, capture ARP on the bridge port (`tcpdump -ni <port> arp`) and prefer a
PCIe NIC for the bridge.

**cloud-init is kept minimal.**
cloud-init only sets hostname, user, SSH key and networking, so nodes come up even
without internet access. Packages and MicroCloud are handled by Ansible.

## Roadmap

- [x] Phase 1 – Terraform: storage, cloud-init, VMs
- [ ] Phase 2 – Ansible: snapd check, MicroCloud 3.4 via preseed, UI access link
- [ ] Phase 3 – Validation and an AI agent that runs and checks the deployment (local LLM via Ollama)
- [ ] Phase 4 – Observability: Juju, MicroK8s and COS Lite on a separate host, `microcloud` charm for metrics
- [ ] Phase 5 – MicroCloud Cluster Manager with an external OIDC provider
- [ ] Extras – MicroK8s as a workload on MicroCloud, decommission playbook, NAT network mode
