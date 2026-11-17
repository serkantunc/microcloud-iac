# microcloud-iac

> 🚧 Work in progress

Infrastructure-as-Code for a **3-node Canonical MicroCloud** lab on KVM/libvirt,
with **MicroK8s** running on top as a workload.

- **Terraform** (libvirt provider 0.9.x) provisions the VMs, disks and networking
- **Ansible** installs and initialises MicroCloud (LXD + MicroCeph + MicroOVN)
- **Validation** checks the cluster after deployment
- *(planned)* an **AI agent** that runs the deployment and interprets failures

## Architecture

```
KVM host (single host)
└─ br-mc (Linux bridge on a dedicated NIC) ── LAN
   ├─ mc1  eth0: mgmt/ceph   eth1: OVN uplink   disks: OS + Ceph OSD
   ├─ mc2  eth0: mgmt/ceph   eth1: OVN uplink   disks: OS + Ceph OSD
   └─ mc3  eth0: mgmt/ceph   eth1: OVN uplink   disks: OS + Ceph OSD
```

Two network modes are planned:

| Mode | Use case |
|------|----------|
| `bridge` | VMs get LAN addresses on a dedicated bridge (reference lab) |
| `nat`    | Single-NIC hosts; everything stays on libvirt NAT networks |

## High availability: what this lab does and does not show

All three nodes run on one physical host, so this lab provides **node-level HA**
(stop one VM: dqlite keeps quorum, Ceph runs degraded, workloads keep running),
**not host-level HA**. A host failure takes down the whole cluster.

## Status

- [ ] Phase 1 – Terraform: VMs, disks, networking
- [ ] Phase 2 – Ansible: MicroCloud + MicroK8s
- [ ] Phase 3 – Validation + AI agent
- [ ] Phase 4 – Docs, diagrams, optional COS on a separate host
