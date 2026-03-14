# K3s Worker Setup (Proxmox base image)

This guide provisions a new K3s worker node from an Ubuntu base image/template.

## Prerequisites

- Control-plane (server) is healthy and reachable on `:6443`.
- Worker can reach the control-plane IP over the LAN.
- Worker and server must run the same K3s version.

## 1) Clone VM from template

- Clone your base Ubuntu VM/template in Proxmox.
- Give it a unique VM name (example: `cluster-worker-2`).
- Start the VM.

## 2) Set unique hostname

Run on the new worker VM:

```bash
sudo hostnamectl set-hostname cluster-worker-5
echo "cluster-worker-5" | sudo tee /etc/hostname
hostnamectl --static
```

Optional but recommended (`/etc/hosts` consistency):

```bash
echo "127.0.1.1 cluster-worker-5" | sudo tee -a /etc/hosts
```

## 3) Ensure stable network identity

Use either:

- DHCP reservation (recommended), or
- static netplan in the VM.

Also ensure node-to-node firewall rules allow K3s overlay traffic:

- `udp/8472` (flannel VXLAN) between all K3s nodes
- `tcp/6443` from workers to control-plane

Validate:

```bash
ip -br a
ip route
```

## 4) Verify connectivity to control-plane

Replace with your control-plane IP:

```bash
nc -vz 192.168.88.245 6443
curl -k https://192.168.88.245:6443/cacerts
```

## 5) Get server version and node token

Run on the control-plane node:

```bash
sudo k3s --version
sudo cat /var/lib/rancher/k3s/server/node-token
```

Use the exact server version for agent install.

## 6) Install k3s agent on worker

Run on worker, replacing token and IP:

```bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="v1.33.6+k3s1" \
  K3S_URL="https://192.168.88.245:6443" \
  K3S_TOKEN="<NODE_TOKEN>" \
  sh -s - agent
```

## 7) Verify join

On control-plane:

```bash
kubectl get nodes -o wide
kubectl get node cluster-worker-2
```

On worker:

```bash
sudo systemctl status k3s-agent --no-pager -l
sudo journalctl -u k3s-agent -n 80 --no-pager
```

## 8) Apply kubelet eviction/image-GC guardrails (recommended)

Run on worker:

```bash
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/config.yaml >/dev/null <<'EOF'
kubelet-arg:
  - "eviction-hard=nodefs.available<10%,imagefs.available<10%,nodefs.inodesFree<5%,imagefs.inodesFree<5%"
  - "eviction-soft=nodefs.available<15%,imagefs.available<15%"
  - "eviction-soft-grace-period=nodefs.available=2m,imagefs.available=2m"
  - "eviction-max-pod-grace-period=30"
  - "image-gc-high-threshold=75"
  - "image-gc-low-threshold=60"
EOF
sudo systemctl restart k3s-agent
```

Validate:

```bash
kubectl describe node cluster-worker-2 | grep -E "DiskPressure|Taints|Conditions"
kubectl get events -A --sort-by=.lastTimestamp | grep -Ei "Evicted|DiskPressure|ephemeral-storage|InvalidDiskCapacity" | tail -n 40
```

## Re-provision from a previously used image

If the image ever had k3s previously installed, clean first:

```bash
sudo systemctl stop k3s-agent || true
sudo /usr/local/bin/k3s-agent-uninstall.sh || true
sudo rm -rf /etc/rancher/k3s /var/lib/rancher/k3s /var/lib/kubelet /var/lib/cni /etc/cni/net.d
```

Then run the install step again.

## Notes

- Worker role showing `<none>` in `kubectl get nodes` is normal.
- If needed, add a worker label:

```bash
kubectl label node cluster-worker-2 node-role.kubernetes.io/worker=worker
```
