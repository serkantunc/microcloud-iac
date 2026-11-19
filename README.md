# microcloud-iac

[![lint](https://github.com/serkantunc/microcloud-iac/actions/workflows/lint.yml/badge.svg)](https://github.com/serkantunc/microcloud-iac/actions/workflows/lint.yml)

Infrastructure-as-Code for a **3-node Canonical MicroCloud** lab on KVM/libvirt,
with **MicroK8s** planned as a workload on top.

Target stack (MicroCloud 3 LTS line): MicroCloud 3.4, LXD 6, MicroCeph Tentacle and
MicroOVN 26.03 on Ubuntu 26.04 LTS.

- **Terraform** (libvirt provider 0.9.x) provisions storage, cloud-init seeds and VMs
- **Ansible** installs and bootstraps MicroCloud (LXD + MicroCeph + MicroOVN) from a preseed file
- **Validation** checks the cluster after deployment and writes a JSON report
- An **AI agent** (local LLM via Ollama) reads the validation report and the cluster state and explains failures, read-only

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
ansible-playbook ui-link.yml
cat .secrets/ui-link.txt
ansible-playbook validate.yml
```

`site.yml` ends with `microcloud status`. From an empty host to a `HEALTHY` three-node
cluster took about 3.5 minutes in the reference lab, including image and snap downloads.

Terraform writes `ansible/inventory/hosts.yml`, so node addresses and network settings are
defined once in Terraform. Ansible generates the MicroCloud session passphrase on first run
and keeps it in `ansible/.secrets/` (not committed).

### Playbooks

#### `site.yml`: build the cluster

- `common`: includes phased updates (all nodes get the same package versions), upgrades and
  reboots if needed, checks that snapd is at least 2.75 (required by MicroCloud 3.4)
- `microcloud`: writes `/etc/hosts`, installs LXD 6, MicroCeph Tentacle, MicroOVN 26.03 and
  MicroCloud 3 with `--cohort=+`, holds automatic refreshes, renders the preseed file and runs
  `microcloud preseed` on all nodes at once (skipped when the node is already a member)

Running it again reports `changed=0`.

#### `ui-link.yml`: initial LXD UI access

- Runs `lxd init --ui-initial-access-link` on the first reachable member, which creates the
  `ui-admin-initial` identity and issues a bearer token valid for 24 hours
- Writes the link to `ansible/.secrets/ui-link.txt` on the controller (mode 0600, not
  committed) instead of printing it: the token is long and Ansible output wraps it, which
  breaks the link when copied
- The token never appears in the output (`no_log`)

Open the link in a browser to log in to the UI as an admin, then set up permanent access
with a browser certificate. The link is meant for initial setup only; permanent access
will move to OIDC (Phase 5).

This playbook is not idempotent by design: every run revokes the previous token and issues
a new one. That is why it is kept separate from `site.yml`.

#### `validate.yml`: check the cluster

Runs on the first cluster member that answers over SSH (`select-target.yml`, shared with
`ui-link.yml`), so it still works when a node is down. It does not stop at the first failure: every check runs, then the playbook fails if
any check failed.

| Check | Passes when |
|-------|-------------|
| `nodes_reachable` | every node answers over SSH |
| `cluster_members` | all members are `Online` |
| `ceph_health` | Ceph reports `HEALTH_OK` |
| `ceph_osds` | one OSD per node, all up and in |
| `ceph_cluster_network` | OSD replication uses the dedicated Ceph network |
| `storage_pools` | `local`, `remote` and `remote-fs` exist and are created |
| `networks` | `UPLINK` and `default` exist |
| `ovn_router_reachable` | the OVN router's uplink address answers ping from the controller |
| `uplink_routes` | `ipv4.routes` is set on `UPLINK`; warning only, needed for network forwards and load balancers |
| `container_*` | a container on Ceph gets an address, reaches the internet and resolves DNS |
| `vm_boot` | a VM on Ceph boots and its agent responds (`-e validate_vm=true`) |

Test instances are always deleted, even when a step fails. Results are written to
`validate/reports/latest.json` (not committed).

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

`validate.yml` shows this. With `micro1` shut down:

```
FAIL  nodes_reachable  validated from micro2, unreachable: micro1
FAIL  cluster_members  3 members, offline: micro1
FAIL  ceph_health  HEALTH_WARN
FAIL  ceph_osds  3 total, 2 up, 3 in
PASS  ovn_router_reachable  192.168.1.70 from controller
PASS  container_launch  on pool remote
PASS  container_egress  ping 1.1.1.1
```

The cluster is reported as degraded, and new workloads still start on Ceph and reach the
network.

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
role sets `APT::Get::Always-Include-Phased-Updates` (variable `common_apt_include_phased_updates`).

**Preseed: `initiator_address` and `lookup_subnet` are mutually exclusive.**
The preseed reference describes `lookup_subnet` as required, but it only applies to multicast
discovery with `initiator`. With `initiator_address`, every system needs an `address` and
`lookup_subnet` must be omitted.

**cloud-init is kept minimal.**
cloud-init only sets hostname, user, SSH key and networking, so nodes come up even
without internet access. Packages and MicroCloud are handled by Ansible.

## AI agent

`agent/agent.py` is a troubleshooting assistant that runs on the controller and uses a
local model through Ollama. It reads the validation report and queries the cluster, then
explains what is wrong and what the operator should do. It cannot change anything.

```bash
ansible-playbook ansible/validate.yml
python3 agent/agent.py
python3 agent/agent.py "Ceph neden HEALTH_WARN?"
AGENT_MODEL=qwen2.5:7b python3 agent/agent.py -v
```

Each `[tool]` line on stderr shows a call the model made; `-v` also prints the results.
`get_vm_state` runs `virsh` without `sudo`, so the user needs to be in the `libvirt` group.

### Design

- **Fixed tools, no shell.** The model can only pick from eight tools
  (`agent/tools.py`). Each runs one fixed read-only command: `lxc cluster list`,
  `ceph status`, `ceph osd tree`, `microcloud status` or `lxc network list` on a node over
  SSH, `virsh domstate` on the controller, or it reads `validate/reports/latest.json`. The only argument the model controls is a node
  name, checked against the inventory. Unknown tools are rejected.
- **Tool output is data.** Instance names, log lines and error messages come from the
  cluster and could carry text written to steer the model. The system prompt tells the
  model to treat tool results as data and to report instructions found in them as
  suspicious.
- **The report always comes first, and answers are checked.** The agent reads the
  validation report itself before the model's first turn. Each failed or warning check
  maps to the tools that explain it (`CHECK_TOOLS` in `agent/agent.py`). If the model
  answers before calling them, the agent sends it back with the checks still open, up to
  twice. In testing, small local models stopped after one tool, misread Ceph quorum or
  told the operator to run the tools; this is enforced in code, not only in the prompt.
- **Tools are not commands.** If the next steps tell the operator to run a tool name
  (for example `check_node_ssh micro1` in a code block), the answer is sent back with a
  request for real shell commands.
- **Same failover as the playbooks.** Queries go to the first node that answers over SSH.
- **Small context.** Tool results are trimmed to the fields that matter and capped at
  4000 characters, so the agent fits a 6 GB GPU with an 8K context.
- **No dependencies.** Standard library only; node addresses come from the Ansible
  inventory via `ansible-inventory`.

| Setting | Default |
|---------|---------|
| `--model` / `AGENT_MODEL` | `qwen3:4b` |
| `--ollama` / `OLLAMA_HOST` | `http://localhost:11434` |
| `--num-ctx` | `8192` |
| `--max-steps` | `10` |

### Model comparison

Scenario: `micro1` shut down with `virsh shutdown`, then `validate.yml` and the agent.
Hardware: laptop RTX 3050, 6 GB VRAM, 8K context. Each model was asked the default
question and "Ceph neden HEALTH_WARN? Türkçe anlat." (in Turkish).

First version (prompt only, the model decides which tools to call):

| | `qwen2.5:7b` | `qwen3:4b` |
|---|---|---|
| Tools called | 1–2 | 1–5 |
| Root cause | partly; suggested restarting `ceph-osd@3`, a unit MicroCeph does not have | wrong for the Ceph question ("micro3 monitor down"); right for the default question |
| Told the operator to run tools | yes | no |

Current version (report read by the agent, per-check verification, facts in the prompt):

| | `qwen2.5:7b` | `qwen3:4b` |
|---|---|---|
| Tools called | 5 | 5–6 |
| Sent back for unverified checks | 1–2 times | 0–1 times |
| Root cause: `micro1` VM shut off | yes | yes |
| First step: `virsh start micro1` | yes | yes |
| Answered in the question's language | no, answered a Turkish question in Chinese | yes |
| Told the operator to run tools | in 2 of 3 runs | no |
| Contradicted its own findings | yes, "two down OSDs" in the summary, one in the findings | no |
| Same answer on a repeated run | no | yes (temperature 0) |
| Model size | 4.7 GB | 2.5 GB |

`qwen3:4b` is the default: smaller and more reliable here. The bigger gain came from
the code around the model, not from the model.

## Continuous integration

Every push and pull request runs static checks on GitHub-hosted runners
(`.github/workflows/lint.yml`). Nothing connects to libvirt or to the cluster.

| Job | Tools |
|-----|-------|
| `terraform` | `terraform fmt`, `terraform validate`, `tflint` |
| `ansible` | `ansible-lint` (production profile) |
| `python` | `ruff check`, `ruff format` (agent) |
| `security` | `gitleaks` (full git history), `checkov` (Terraform, Ansible, workflow) |

`validate.yml` checks the running cluster; CI checks the code.

## Related work

Canonical's [MicroCloud repository](https://github.com/canonical/microcloud) ships a
Terraform demo under `demos/terraform/` that builds a similar test cluster with the LXD
provider and cloud-init. This repository targets plain KVM/libvirt hosts without LXD,
separates provisioning (Terraform) from configuration (Ansible), and puts Ceph cluster
traffic on its own network.

## Roadmap

- [x] Phase 1 – Terraform: storage, cloud-init, VMs
- [x] Phase 2 – Ansible: snapd check, MicroCloud 3.4 via preseed
  - [x] LXD UI access link via Ansible
- [x] Phase 3 – Validation and a read-only AI agent that explains failures (local LLM via Ollama)
  - [x] Validation playbook with a JSON report
  - [x] Read-only AI agent that reads the report and the cluster state
  - [x] Compare local models on the same failure scenarios
- [ ] Phase 4 – Observability: Juju, MicroK8s and COS Lite on a separate host, `microcloud` charm for metrics
- [ ] Phase 5 – MicroCloud Cluster Manager with an external OIDC provider
- [ ] Extras – MicroK8s as a workload on MicroCloud, decommission playbook, NAT network mode,
  separate OVN underlay network
