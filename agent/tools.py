"""Read-only tools the agent can call.

Each tool runs a fixed command. The model chooses which tool to call and,
for check_node_ssh, which inventory node; it never supplies command text.
"""

import json
import subprocess
from pathlib import Path

MAX_OUTPUT_CHARS = 4000

REMOTE_COMMANDS = {
    "cluster_members": "lxc cluster list -f json",
    "ceph_status": "microceph.ceph status -f json",
    "ceph_osd_tree": "microceph.ceph osd tree -f json",
    "microcloud_status": "microcloud status",
    "networks": "lxc network list -f json",
}


def _truncate(text):
    if len(text) <= MAX_OUTPUT_CHARS:
        return text
    return text[:MAX_OUTPUT_CHARS] + "\n[truncated]"


def load_inventory(path):
    result = subprocess.run(
        ["ansible-inventory", "-i", str(path), "--list"],
        capture_output=True,
        text=True,
        check=True,
    )
    data = json.loads(result.stdout)
    hostvars = data.get("_meta", {}).get("hostvars", {})
    names = data.get("microcloud", {}).get("hosts", [])
    nodes = {}
    for name in names:
        hv = hostvars.get(name, {})
        nodes[name] = {
            "address": hv.get("ansible_host", name),
            "user": hv.get("ansible_user", "ubuntu"),
        }
    return nodes


class Cluster:
    def __init__(self, nodes, report_path):
        self.nodes = nodes
        self.report_path = Path(report_path)
        self._target = None

    def _ssh(self, node, command, timeout=30):
        info = self.nodes[node]
        args = [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=5",
            "-o",
            "StrictHostKeyChecking=accept-new",
            f"{info['user']}@{info['address']}",
            command,
        ]
        return subprocess.run(
            args, capture_output=True, text=True, timeout=timeout, check=False
        )

    def _reachable(self, node):
        try:
            return self._ssh(node, "true", timeout=10).returncode == 0
        except subprocess.TimeoutExpired:
            return False

    def _target_node(self):
        if self._target is None:
            for node in self.nodes:
                if self._reachable(node):
                    self._target = node
                    break
        return self._target

    def _remote(self, key):
        node = self._target_node()
        if node is None:
            return {"error": "no cluster member is reachable over SSH"}
        try:
            result = self._ssh(node, "sudo -n " + REMOTE_COMMANDS[key])
        except subprocess.TimeoutExpired:
            return {"error": f"command timed out on {node}"}
        if result.returncode != 0:
            return {"queried_node": node, "error": result.stderr.strip()[:500]}
        return {"queried_node": node, "output": result.stdout}

    def get_validation_report(self):
        if not self.report_path.exists():
            return {
                "error": f"no report at {self.report_path}, run ansible-playbook validate.yml"
            }
        return json.loads(self.report_path.read_text())

    def get_cluster_members(self):
        raw = self._remote("cluster_members")
        if "output" not in raw:
            return raw
        members = json.loads(raw["output"])
        return {
            "queried_node": raw["queried_node"],
            "members": [
                {
                    "name": m.get("server_name"),
                    "status": m.get("status"),
                    "message": m.get("message"),
                    "roles": m.get("roles"),
                }
                for m in members
            ],
        }

    def get_ceph_status(self):
        raw = self._remote("ceph_status")
        if "output" not in raw:
            return raw
        status = json.loads(raw["output"])
        checks = status.get("health", {}).get("checks", {})
        osdmap = status.get("osdmap", {})
        pgmap = status.get("pgmap", {})
        return {
            "queried_node": raw["queried_node"],
            "health": status.get("health", {}).get("status"),
            "checks": {
                name: check.get("summary", {}).get("message")
                for name, check in checks.items()
            },
            "osds": {
                "total": osdmap.get("num_osds"),
                "up": osdmap.get("num_up_osds"),
                "in": osdmap.get("num_in_osds"),
            },
            "monitors_in_quorum": status.get("quorum_names"),
            "placement_groups": pgmap.get("pgs_by_state"),
        }

    def get_ceph_osd_tree(self):
        raw = self._remote("ceph_osd_tree")
        if "output" not in raw:
            return raw
        tree = json.loads(raw["output"])
        by_id = {n["id"]: n for n in tree.get("nodes", [])}
        osds = []
        for node in tree.get("nodes", []):
            if node.get("type") != "host":
                continue
            for child in node.get("children", []):
                osd = by_id.get(child, {})
                osds.append(
                    {
                        "osd": osd.get("name"),
                        "host": node.get("name"),
                        "status": osd.get("status"),
                    }
                )
        return {"queried_node": raw["queried_node"], "osds": osds}

    def get_microcloud_status(self):
        raw = self._remote("microcloud_status")
        if "output" not in raw:
            return raw
        return {"queried_node": raw["queried_node"], "output": raw["output"]}

    def get_networks(self):
        raw = self._remote("networks")
        if "output" not in raw:
            return raw
        networks = json.loads(raw["output"])
        return {
            "queried_node": raw["queried_node"],
            "networks": [
                {
                    "name": n.get("name"),
                    "type": n.get("type"),
                    "managed": n.get("managed"),
                    "status": n.get("status"),
                }
                for n in networks
                if n.get("managed")
            ],
        }

    def get_vm_state(self):
        states = {}
        for node in self.nodes:
            try:
                result = subprocess.run(
                    ["virsh", "-c", "qemu:///system", "domstate", node],
                    capture_output=True,
                    text=True,
                    timeout=10,
                    check=False,
                )
            except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
                return {"error": f"virsh not usable on the controller: {exc}"}
            if result.returncode == 0:
                states[node] = result.stdout.strip()
            else:
                states[node] = "unknown: " + result.stderr.strip()[:200]
        return {"host": "controller (KVM host)", "vm_states": states}

    def check_node_ssh(self, node):
        if node not in self.nodes:
            return {
                "error": f"unknown node {node!r}, known nodes: {sorted(self.nodes)}"
            }
        return {
            "node": node,
            "address": self.nodes[node]["address"],
            "reachable": self._reachable(node),
        }

    def call(self, name, arguments):
        handlers = {
            "get_validation_report": self.get_validation_report,
            "get_cluster_members": self.get_cluster_members,
            "get_ceph_status": self.get_ceph_status,
            "get_ceph_osd_tree": self.get_ceph_osd_tree,
            "get_microcloud_status": self.get_microcloud_status,
            "get_networks": self.get_networks,
            "get_vm_state": self.get_vm_state,
            "check_node_ssh": lambda: self.check_node_ssh(
                str(arguments.get("node", ""))
            ),
        }
        handler = handlers.get(name)
        if handler is None:
            return _truncate(json.dumps({"error": f"unknown tool {name!r}"}))
        try:
            return _truncate(json.dumps(handler(), indent=1))
        except (json.JSONDecodeError, subprocess.SubprocessError, OSError) as exc:
            return _truncate(json.dumps({"error": f"{type(exc).__name__}: {exc}"}))


def tool_specs(node_names):
    def spec(name, description, properties=None, required=None):
        return {
            "type": "function",
            "function": {
                "name": name,
                "description": description,
                "parameters": {
                    "type": "object",
                    "properties": properties or {},
                    "required": required or [],
                },
            },
        }

    return [
        spec(
            "get_validation_report",
            "Latest validation report written by ansible-playbook validate.yml: every check with pass, warn or fail.",
        ),
        spec(
            "get_cluster_members",
            "LXD cluster members with their status (Online, Offline, Evacuated) and roles.",
        ),
        spec(
            "get_ceph_status",
            "Ceph health, active health checks, OSD counts, monitor quorum and placement group states.",
        ),
        spec(
            "get_ceph_osd_tree",
            "Each Ceph OSD with the host it runs on and whether it is up or down.",
        ),
        spec(
            "get_microcloud_status",
            "Output of microcloud status: per-node services and warnings.",
        ),
        spec(
            "get_networks",
            "Managed LXD networks (UPLINK, OVN networks) and their status.",
        ),
        spec(
            "get_vm_state",
            "State of each node's KVM virtual machine on the controller host "
            "(running, shut off, paused), from virsh domstate.",
        ),
        spec(
            "check_node_ssh",
            "Check whether one cluster node answers over SSH from the controller.",
            {"node": {"type": "string", "enum": sorted(node_names)}},
            ["node"],
        ),
    ]
