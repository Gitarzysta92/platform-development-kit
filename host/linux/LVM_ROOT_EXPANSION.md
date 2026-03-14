# LVM Root Expansion on Ubuntu VMs (Proxmox)

This runbook ensures Ubuntu VMs actually use the full virtual disk size.

In this environment, several nodes had a larger Proxmox disk (for example `20G`), but root filesystem (`/`) remained much smaller (for example `10G`) because LVM free space was left unallocated.

This can trigger Kubernetes `ephemeral-storage` pressure and pod evictions under load.

## When to run

- Immediately after cloning/provisioning a new VM from template.
- During incident response when you see `DiskPressure`, `Evicted`, or low `ephemeral-storage`.

## 1) Inspect current layout

```bash
lsblk
sudo pvs
sudo vgs
sudo lvs
df -h /
```

If `VFree` in `vgs` is not `0`, root LV is not using all available disk.

## 2) Expand root LV and filesystem

```bash
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv -r
df -h /
```

Notes:

- `-l +100%FREE` uses all remaining free extents in the volume group.
- `-r` resizes the filesystem online after LV expansion.

## 3) Verify Kubernetes node health

Run from control-plane:

```bash
kubectl get nodes
kubectl describe node <node-name> | grep -E "DiskPressure|Taints|Conditions"
kubectl get events -A --sort-by=.lastTimestamp | grep -Ei "Evicted|DiskPressure|InvalidDiskCapacity" | tail -n 40
```

Expected:

- `DiskPressure` is `False`
- no `disk-pressure` taint
- no new eviction storms

## Troubleshooting

- If `lvextend` reports no free extents, first confirm VM disk was expanded in Proxmox.
- If partition (`/dev/sda3`) does not cover the full disk after VM disk resize, expand partition and PV, then retry:

```bash
sudo growpart /dev/sda 3
sudo pvresize /dev/sda3
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv -r
```

Install `growpart` if missing:

```bash
sudo apt-get update
sudo apt-get install -y cloud-guest-utils
```
