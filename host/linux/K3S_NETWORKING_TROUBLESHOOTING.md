# K3s Networking Troubleshooting (Cross-node DNS / Argo 504)

This runbook covers a specific failure mode in K3s + flannel:

- Argo UI returns `504`
- pods on workers cannot resolve DNS (`kube-dns` timeouts)
- control-plane local pods still resolve DNS

## Typical symptoms

- Ingress logs show upstream timeouts to Argo backend pod IP.
- Application logs show DNS lookup timeouts (for example `lookup argocd-redis: i/o timeout`).
- Pod DNS tests on workers fail:

```bash
kubectl -n platform run dns-test --restart=Never --image=busybox:1.36 \
  --overrides='{"spec":{"nodeName":"cluster-worker-1"}}' \
  -- sh -c 'nslookup kubernetes.default.svc.cluster.local'
```

- Same DNS test on control-plane succeeds.

## Root cause pattern (validated)

On control-plane host:

- `INPUT` policy is `DROP`
- no explicit allow for flannel VXLAN (`udp/8472`)

When this happens, cross-node overlay traffic arrives but is dropped before proper handling, which breaks pod-to-pod and pod-to-service DNS from workers.

## Validate quickly

On control-plane (`wapps`):

```bash
sudo iptables -S INPUT
sudo iptables -nvL INPUT | grep 8472
sudo ss -lunp | grep 8472
```

If policy is `DROP` and no `udp/8472` allow rule is present, this is likely the issue.

## Immediate fix

Run on control-plane:

```bash
sudo iptables -I INPUT 1 -i enp6s18 -p udp --dport 8472 -j ACCEPT
sudo iptables -I INPUT 2 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

Re-test DNS from worker pod:

```bash
kubectl -n platform run dns-direct-w1 --restart=Never --image=busybox:1.36 \
  --overrides='{"spec":{"nodeName":"cluster-worker-1"}}' \
  -- sh -c 'nslookup kubernetes.default.svc.cluster.local 10.42.0.251'
kubectl -n platform logs dns-direct-w1
```

Expected result: successful DNS answer.

## Persist the fix

Temporary `iptables` rules are lost on reboot/reload.

### Option A: iptables-persistent

```bash
sudo apt-get update
sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save
```

### Option B: firewall-as-source-of-truth

Use your primary firewall manager (UFW/Tailscale policy/Ansible) and keep rules declarative.

#### UFW example (recommended on Ubuntu nodes)

Allow flannel VXLAN from cluster LAN peers:

```bash
sudo ufw allow in on enp6s18 proto udp from 192.168.88.0/24 to any port 8472 comment 'k3s flannel vxlan'
```

Allow pod CIDR forwarding when host policy is default deny:

```bash
sudo ufw route allow in on enp6s18 out on cni0 to 10.42.0.0/16 comment 'k3s overlay to pods'
sudo ufw route allow in on cni0 out on enp6s18 from 10.42.0.0/16 comment 'k3s pods to overlay'
```

Reload and verify:

```bash
sudo ufw reload
sudo ufw status verbose
sudo iptables -S INPUT | head -n 30
```

#### Tailscale coexistence note

If Tailscale and UFW are both present, ensure your host policy does not shadow Kubernetes overlay traffic.
In this incident pattern, `INPUT DROP` with no explicit `udp/8472` accept caused cross-node DNS failures.

## Required network ports for K3s (minimum)

Between K3s nodes:

- `6443/tcp` (server API, workers -> server)
- `8472/udp` (flannel VXLAN overlay)

If ports are blocked or reordered by firewall chains, cross-node pod networking fails.

## Post-fix verification checklist

```bash
kubectl get nodes -o wide
kubectl -n platform get pods -o wide | grep -E "argocd-server|argocd-repo-server|argocd-dex-server"
kubectl -n platform logs dns-direct-w1
kubectl -n platform logs dns-direct-w2
```

Optional:

```bash
kubectl -n kube-system scale deployment coredns --replicas=2
```

This improves DNS resilience, but does not replace proper overlay/firewall configuration.
