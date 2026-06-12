# Thin master plus infra edge topology

This topology models each environment as:

- one thin K3s control-plane node in inventory group `k3s_server`
- one infra/edge K3s agent in inventory group `k3s_infra`
- worker/storage-capable K3s agents joined outside PDK

`threesixty-infrastructure` owns Proxmox VM lifecycle and guest OS preparation. PDK owns K3s server installation, ingress-nginx, Tailscale, host nginx, DNS, and certificates.

Run phases in order:

```bash
ansible-playbook -i inventory.ini host/topologies/thin-master-infra-edge/01-k3s-server.yml
```

Join the infra and worker nodes as K3s agents, then install ingress-nginx on the server:

```bash
ansible-playbook -i inventory.ini host/topologies/thin-master-infra-edge/02-ingress-controller.yml
```

Configure the infra/edge front door:

```bash
ansible-playbook -i inventory.ini host/topologies/thin-master-infra-edge/03-infra-front-door.yml
```

The infra-edge playbook derives `nginx_k3s_api_upstream` from the first host in `k3s_server` by default. Override it when needed:

```bash
ansible-playbook -i inventory.ini host/topologies/thin-master-infra-edge/03-infra-front-door.yml \
  -e nginx_k3s_api_upstream="<cluster-master-ip>:6443"
```

Infra-edge nginx upstream defaults:

```yaml
nginx_ingress_http_upstream: "127.0.0.1:32080"
nginx_ingress_https_upstream: "127.0.0.1:32443"
nginx_rabbitmq_amqp_upstream: "127.0.0.1:30567"
nginx_ssh_proxy_upstream: "127.0.0.1:30222"
dnsmasq_address_all: true
dnsmasq_port: 53
```
