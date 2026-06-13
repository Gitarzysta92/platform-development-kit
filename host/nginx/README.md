# Host Nginx (reverse proxy)

This directory configures **host-level nginx** as a front door for a K3s host:

- Does **not** terminate TLS on the host. TLS termination happens in **ingress-nginx / the cluster**.
- Proxies **HTTP cluster traffic** to the configured ingress-nginx HTTP upstream (`nginx_ingress_http_upstream`, default `127.0.0.1:32080`).
- Proxies **HTTPS cluster traffic** via **SNI-based TCP passthrough** to the configured ingress-nginx HTTPS upstream (`nginx_ingress_https_upstream`, default `127.0.0.1:32443`).
- Optionally proxies **host-level services** (K3s API).
- Optionally exposes TCP services via `stream` (RabbitMQ AMQP on `5672`).

## TLS passthrough details

Port `443` is handled by nginx **stream** with **SNI-based TCP passthrough** (`ssl_preread`):

- `k3s-api.*` -> `nginx_k3s_api_upstream` (default `127.0.0.1:6443`; note: clients will see the **K3s** certificate)
- everything else -> `nginx_ingress_https_upstream` (default `127.0.0.1:32443`)

This requires `ngx_stream_ssl_preread_module` (typically present in `nginx-full` on Debian/Ubuntu).

## Naming model (env-less hostnames)

The nginx template is intentionally **env-less** for host-level services and matches by prefix:

- `argocd.*` (HTTPS) -> `nginx_ingress_https_upstream`
- `k3s-api.*` (HTTPS) -> `nginx_k3s_api_upstream`
- `api.*` / `*.api.*` -> `nginx_ingress_http_upstream`
- everything else -> `nginx_ingress_http_upstream`

This works best together with suffix-based DNS routing (e.g. Tailscale Split DNS), where DNS decides which host/cluster receives a given domain suffix.

## Upstream model

The defaults keep the classic colocated front-door layout, where host nginx runs on the same node as the K3s server and NodePorts are available on loopback:

```yaml
nginx_k3s_api_upstream: "127.0.0.1:6443"
nginx_ingress_http_upstream: "127.0.0.1:32080"
nginx_ingress_https_upstream: "127.0.0.1:32443"
nginx_rabbitmq_amqp_upstream: "127.0.0.1:30567"
nginx_ssh_proxy_upstream: "127.0.0.1:30222"
```

## Firewall

The nginx installer owns firewall rules for the host-level ports it exposes:

- `80/tcp` for HTTP
- `443/tcp` for TLS passthrough
- `2222/tcp` for the SSH proxy
- `5672/tcp` for RabbitMQ AMQP

Set `nginx_manage_firewall=false` if another layer owns nginx front-door firewall rules. Set `nginx_ssh_proxy_firewall_enabled=false` or `nginx_rabbitmq_amqp_firewall_enabled=false` to skip those optional TCP proxy ports.

For a thin-master plus infra-edge layout, run host nginx on the infra K3s agent and point only the K3s API upstream at the control-plane node:

```yaml
nginx_k3s_api_upstream: "<k3s-server-ip>:6443"
nginx_ingress_http_upstream: "127.0.0.1:32080"
nginx_ingress_https_upstream: "127.0.0.1:32443"
nginx_rabbitmq_amqp_upstream: "127.0.0.1:30567"
nginx_ssh_proxy_upstream: "127.0.0.1:30222"
```

## Manual update (no Ansible)

1) Update the site config:

- Edit: `/etc/nginx/sites-available/<name>`
- Enable: symlink into `/etc/nginx/sites-enabled/<name>`

2) Update stream config (optional, RabbitMQ):

- Edit: `/etc/nginx/stream.d/stream.conf`

3) Validate and reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## Notes
- If `nginx -t` fails, do not reload/restart until the config is fixed.
- For Debian/Ubuntu, the playbook uses `nginx-full` to ensure stream module support.
