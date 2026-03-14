# Static IP with Netplan (Ubuntu)

This guide configures a static IPv4 address on an Ubuntu VM using netplan.

## 1) Identify current interface and route

```bash
ip -br a
ip route
```

Collect:

- interface name (example: `enp6s18`)
- target static IP (example: `192.168.88.245`)
- default gateway (example: `192.168.88.1`)
- DNS servers

## 2) Backup current netplan config

```bash
sudo cp /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak
```

If your system uses a different file under `/etc/netplan`, backup that file instead.

## 3) Edit netplan

```bash
sudo nano /etc/netplan/50-cloud-init.yaml
```

Example configuration:

```yaml
network:
  version: 2
  ethernets:
    enp6s18:
      dhcp4: false
      addresses:
        - 192.168.88.238/24
      routes:
        - to: default
          via: 192.168.88.1
      nameservers:
        addresses:
          - 192.168.88.1
          - 1.1.1.1
```

## 4) Apply safely (with rollback window)

```bash
sudo netplan generate
sudo netplan try
```

If connectivity is good, confirm the prompt to keep config. If not confirmed, netplan automatically reverts.

Then apply permanently:

```bash
sudo netplan apply
```

## 5) Validate

```bash
ip -br a
ip route
ping -c 2 192.168.88.1
```

For k3s control-plane host validation from another node:

```bash
nc -vz 192.168.88.245 6443
```

## Troubleshooting

- If SSH is lost after changes, use Proxmox console and restore backup:

```bash
sudo cp /etc/netplan/50-cloud-init.yaml.bak /etc/netplan/50-cloud-init.yaml
sudo netplan apply
```

- If `netplan try` reports YAML errors, fix indentation (spaces only, no tabs).

## Recommendation

- Control-plane should always have stable IP (static netplan or DHCP reservation).
- Workers should also have stable IP to avoid churn after reboots/leases.
