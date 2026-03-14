# K3s Stability Hardening (DiskPressure / Eviction Prevention)

This runbook documents practical hardening steps to reduce pod eviction storms and improve stability under bursty workloads (for example ARC runner churn).

Use this together with `LVM_ROOT_EXPANSION.md`.
For workload priority and runner ephemeral-storage baseline, see `K8S_PRIORITY_AND_EPHEMERAL_STORAGE.md`.

## Goals

- Prevent `DiskPressure` and eviction storms.
- Keep core platform workloads stable during CI spikes.
- Make kubelet behavior predictable under low disk conditions.

## 1) Baseline capacity first

Before tuning kubelet, ensure each node root filesystem is fully expanded and has enough free headroom.

- Minimum recommended worker root size: `20-30G`
- CI-heavy nodes: `40G+` is safer

Reference: `LVM_ROOT_EXPANSION.md`

## 2) Set explicit kubelet eviction and image GC thresholds

Configure on each node in `/etc/rancher/k3s/config.yaml` (or files under `/etc/rancher/k3s/config.yaml.d/`):

```yaml
kubelet-arg:
  - "eviction-hard=nodefs.available<10%,imagefs.available<10%,nodefs.inodesFree<5%,imagefs.inodesFree<5%"
  - "eviction-soft=nodefs.available<15%,imagefs.available<15%"
  - "eviction-soft-grace-period=nodefs.available=2m,imagefs.available=2m"
  - "eviction-max-pod-grace-period=30"
  - "image-gc-high-threshold=75"
  - "image-gc-low-threshold=60"
  - "system-reserved=cpu=200m,memory=512Mi,ephemeral-storage=1Gi"
  - "kube-reserved=cpu=200m,memory=512Mi,ephemeral-storage=1Gi"
```

Apply:

```bash
sudo systemctl restart k3s-agent
```

Validate:

```bash
kubectl describe node <node-name> | grep -E "DiskPressure|Taints|Conditions"
kubectl get events -A --sort-by=.lastTimestamp | grep -Ei "Evicted|DiskPressure|InvalidDiskCapacity" | tail -n 40
```

## 3) Isolate ARC runner workloads

Avoid placing CI-heavy runner pods on nodes hosting critical platform components.

Example:

```bash
kubectl label node cluster-worker-2 workload=ci
kubectl label node cluster-worker-3 workload=ci
kubectl taint node cluster-worker-2 workload=ci:NoSchedule
kubectl taint node cluster-worker-3 workload=ci:NoSchedule
```

Then configure ARC workloads with matching `nodeSelector` and `tolerations` for `workload=ci`.

## 4) Define ephemeral-storage requests and limits

Add `ephemeral-storage` requests/limits for runner pods and critical platform workloads.

Example snippet:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
    ephemeral-storage: "256Mi"
  limits:
    cpu: "1000m"
    memory: "1Gi"
    ephemeral-storage: "1Gi"
```

Why: this improves scheduling decisions and makes eviction behavior less chaotic.

## 5) Routine cleanup and log retention

Run periodic cleanup on worker nodes:

```bash
sudo k3s crictl rmi --prune
sudo k3s crictl image prune
sudo journalctl --vacuum-time=3d
```

Optional persistent journald limits:

```bash
sudo mkdir -p /etc/systemd/journald.conf.d
printf "[Journal]\nSystemMaxUse=200M\nRuntimeMaxUse=100M\n" | sudo tee /etc/systemd/journald.conf.d/limits.conf
sudo systemctl restart systemd-journald
```

## 6) Monitoring and alerts

Alert when:

- any node has `DiskPressure=True`
- `nodefs.available < 15%`
- `imagefs.available < 15%`
- eviction events increase rapidly (`Warning Evicted`, `EvictionThresholdMet`)

## 7) Incident response quick commands

```bash
kubectl get nodes -o wide
kubectl describe nodes | grep -En "Name:|DiskPressure|MemoryPressure|PIDPressure|Taints|eviction|InvalidDiskCapacity"
kubectl get events -A --sort-by=.lastTimestamp | grep -Ei "Evicted|DiskPressure|InvalidDiskCapacity|image filesystem" | tail -n 80
```

On affected node:

```bash
df -h
df -i
sudo journalctl -u k3s-agent --since "2 hours ago" | grep -Ei "invalid capacity|image filesystem|evict|disk pressure|garbage|containerd"
sudo du -h --max-depth=2 /var/lib/rancher/k3s 2>/dev/null | sort -h | tail -n 30
```

## Notes

- `InvalidDiskCapacity: invalid capacity 0 on image filesystem` can appear transiently during startup, but recurring events plus real `Evicted` events indicate an actual stability risk.
- Small disks and high image churn are the most common trigger combination.
