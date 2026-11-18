# microcloud-iac

Infrastructure-as-Code for a **3-node Canonical MicroCloud** lab on KVM/libvirt,
with **MicroK8s** planned as a workload on top.

Target stack (MicroCloud 3 LTS line): MicroCloud 3.4, LXD 6, MicroCeph Tentacle and
MicroOVN 26.03 on Ubuntu 26.04 LTS.

- **Terraform** (libvirt provider 0.9.x) provisions storage, cloud-init seeds and VMs
- **Ansible** installs and bootstraps MicroCloud (LXD + MicroCeph + MicroOVN) from a preseed file
- **Validation** *(Phase 3)* checks the cluster after deployment
- *(planned)* an **AI agent** that runs the deployment and interprets failures

## Architecture

```
KVM host
├─ br-mc (Linux bridge) ─────────── LAN 192.168.1.0/24
│                                     ├─ mgmt: management, MicroCloud, Ceph public, OVN underlay
│                                     └─ uplink: OVN uplink (no IP on the node)
└─ mc-ceph (isolated libvirt network) 10.10.10.0/24
                                      └─ ceph: Ceph cluster traffic (replication, heartbeat)

micro1  mgmt .61  uplink -  ceph 10.10.10.61  disks: vda OS, vdb Ceph, vdc local
micro2  mgmt .62  uplink -  ceph 10.10.10.62  disks: vda OS, vdb Ceph, vdc local
micro3  mgmt .63  uplink -  ceph 10.10.10.63  disks: vda OS, vdb Ceph, vdc local
```

| Component | Details |
|-----------|---------|
| OS | Ubuntu 26.04 LTS cloud image, shared as a read-only backing file (copy-on-write per node) |
| Interfaces | Matched by MAC address and renamed by netplan (`mgmt`, `uplink`, `ceph`) |
| Storage | `local` (ZFS on vdc), `remote` (Ceph RBD on vdb), `remote-fs` (CephFS) |
| OVN | Uplink gateway 192.168.1.1, floating range 192.168.1.70–109 |
| Names | Node FQDNs under `home.arpa`, resolving to the management IP (not 127.0.1.1) |

MAC addresses are derived from the node IP (`52:54:00:00:01:61` for `mgmt` on `.61`).
Disks have serial numbers, so the preseed refers to them as `/dev/disk/by-id/virtio-<node>-<role>`.

## Requirements

- KVM host with libvirt (tested with libvirt 12 / QEMU 10.2 on Ubuntu 26.04)
- Nested virtualization enabled (`/sys/module/kvm_intel/parameters/nested` = `Y`)
- Terraform >= 1.6, Ansible (with `community.general`), `xorriso`
- A Linux bridge connected to your LAN (default name `br-mc`)
- An SSH key pair; the public key is injected into every node
- Free static IPs outside your DHCP range (3 for nodes, plus a range for OVN uplink)

## Quick start

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit terraform.tfvars for your network

terraform -chdir=terraform init
terraform -chdir=terraform apply

cd ansible
ansible all -m wait_for_connection
ansible-playbook site.yml
```

The playbook ends with `microcloud status`. From an empty host to a `HEALTHY` three-node
cluster took about 3.5 minutes in the reference lab, including image and snap downloads.

Terraform writes `ansible/inventory/hosts.yml`, so node addresses and network settings are
defined once in Terraform. Ansible generates the MicroCloud session passphrase on first run
and keeps it in `ansible/.secrets/` (not committed).

### What the playbook does

- `common`: includes phased updates (all nodes get the same package versions), upgrades and
  reboots if needed, checks that snapd is at least 2.75 (required by MicroCloud 3.4)
- `microcloud`: writes `/etc/hosts`, installs LXD 6, MicroCeph Tentacle, MicroOVN 26.03 and
  MicroCloud 3 with `--cohort=+`, holds automatic refreshes, renders the preseed file and runs
  `microcloud preseed` on all nodes at once (skipped when the node is already a member)

Running the playbook again reports `changed=0`.

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
| `ceph_network_cidr` | `10.10.10.0/24` |
| `ovn_ipv4_range` | `192.168.1.70-192.168.1.109` |
| `domain` | `home.arpa` |
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

**Hostname resolving to 127.0.1.1.**
By default cloud-init maps the hostname to 127.0.1.1, which is meant for hosts without a
permanent address and has caused problems for clustered services such as Ceph. Nodes here
resolve their own name to the management IP; cloud-init writes that entry once and Ansible
manages the cluster members block.

**Phased updates leave nodes on different package versions.**
Ubuntu rolls some updates out to a percentage of machines, chosen by machine ID. Nodes built
from the same image at the same time ended up with different snapd versions. The `common`
role sets `APT::Get::Always-Include-Phased-Updates` (variable `apt_include_phased_updates`).

**Preseed: `initiator_address` and `lookup_subnet` are mutually exclusive.**
The preseed reference describes `lookup_subnet` as required, but it only applies to multicast
discovery with `initiator`. With `initiator_address`, every system needs an `address` and
`lookup_subnet` must be omitted.

**cloud-init is kept minimal.**
cloud-init only sets hostname, user, SSH key and networking, so nodes come up even
without internet access. Packages and MicroCloud are handled by Ansible.

## Related work

Canonical's [MicroCloud repository](https://github.com/canonical/microcloud) ships a
Terraform demo under `demos/terraform/` that builds a similar test cluster with the LXD
provider and cloud-init. This repository targets plain KVM/libvirt hosts without LXD,
separates provisioning (Terraform) from configuration (Ansible), and puts Ceph cluster
traffic on its own network.

## Roadmap

- [x] Phase 1 – Terraform: storage, cloud-init, VMs
- [x] Phase 2 – Ansible: snapd check, MicroCloud 3.4 via preseed
  - [ ] LXD UI access link and admin identity via Ansible
- [ ] Phase 3 – Validation and an AI agent that runs and checks the deployment (local LLM via Ollama)
- [ ] Phase 4 – Observability: Juju, MicroK8s and COS Lite on a separate host, `microcloud` charm for metrics
- [ ] Phase 5 – MicroCloud Cluster Manager with an external OIDC provider
- [ ] Extras – MicroK8s as a workload on MicroCloud, decommission playbook, NAT network mode,
  separate OVN underlay network
