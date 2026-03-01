# Host Nginx (reverse proxy)

This directory configures **host-level nginx** as a front door for a single-node K3s host:

- Terminates TLS on the host (certs are provisioned by `host/certificates/install.yml`).
- Proxies **cluster traffic** to ingress-nginx NodePorts (`32080`/`32443`).
- Optionally proxies **host-level services** (K3s API, node-exporter).
- Optionally exposes TCP services via `stream` (RabbitMQ AMQP on `5672`).

## Naming model (env-less hostnames)

The nginx template is intentionally **env-less** for host-level services and matches by prefix:

- `argocd.*` (HTTPS) -> ingress-nginx HTTPS NodePort `32443`
- `k3s-api.*` (HTTPS) -> `127.0.0.1:6443`
- `metrics.*` (HTTP) -> `127.0.0.1:9100`
- `api.*` / `*.api.*` -> ingress-nginx HTTP NodePort `32080`
- everything else -> ingress-nginx HTTP NodePort `32080` (after TLS termination on the host)

This works best together with suffix-based DNS routing (e.g. Tailscale Split DNS), where DNS decides which host/cluster receives a given domain suffix.

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
