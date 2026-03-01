# DNS Configuration

This directory contains Ansible playbooks and templates for configuring DNS resolution using dnsmasq and systemd-resolved.

## Files

- `install.yml` - Main Ansible playbook for DNS setup
- `templates/` - Jinja2 templates for configuration files
  - `dnsmasq-main.conf.j2` - Local wildcard mode (`*.{{ target_env }}.<domain> -> {{ target_ip }}`), default port 5353
  - `dnsmasq-splitdns.conf.j2` - Split DNS nameserver mode (answer-all `-> {{ target_ip }}`), default port 53

## Configuration

The DNS setup creates a wildcard DNS resolution for `{{ target_env }}.wapps.ai` domains that resolves to `{{ target_ip }}`.

### Key Features

- Uses dnsmasq on port 5353 by default to avoid conflicts with systemd-resolved
- Binds only to loopback interface (`lo`)
- Forwards other queries to upstream DNS servers (1.1.1.1, 9.9.9.9)
- Integrates with systemd-resolved for seamless DNS resolution

### Fixed Issues

- Removed conflicting `bind-dynamic` directive that was causing "illegal repeated keyword" error
- Separated configuration into template files for better maintainability
- Used proper `interface=lo` binding instead of `bind-dynamic`

## Usage

Run the playbook with required variables:

```bash
ansible-playbook -i inventory.ini install.yml -e target_env=dev -e target_ip=192.168.1.100
```

### Alternative architecture: Tailscale Split DNS + dnsmasq as the tailnet nameserver
This is the model we ended up using in practice:

- **Single place of truth for domains**: Tailscale admin console “Split DNS” decides which suffixes (e.g. `wapps.ai`, `threesixty.dev`) are routed to a tailnet DNS server (example: `100.83.116.66`).
- **dnsmasq is generic**: it does not need to hardcode `wapps.ai` at all; it can answer *everything it receives* with one IP (safe because Split DNS ensures it only receives queries for your split suffixes).

In this setup you typically:
- keep `systemd-resolved` as-is on clients
- enable `accept-dns=true` on Tailscale clients so they learn the split routes
- run `dnsmasq` on the Split DNS server on **port 53**

- In the Tailscale admin console DNS page, configure:
  - **MagicDNS** (optional but commonly enabled for device names like `<machine>.<tailnet>.ts.net`)
  - **Split DNS** for your own zones (e.g. `wapps.ai`, `threesixty.dev`) pointing at a DNS server you control on the tailnet (example: `100.83.116.66`).
- Ensure nodes **accept Tailscale DNS settings**: `sudo tailscale up --accept-dns=true` (or re-apply: `sudo tailscale up --reset --accept-dns=true`).
- Important: **MagicDNS does not let you add arbitrary `wapps.ai` records by itself**; the custom records live on *your* DNS server (the one you configured for Split DNS). See [MagicDNS docs](https://tailscale.com/docs/features/magicdns) and the long-running feature request about “custom records in MagicDNS” ([tailscale/tailscale#1543](https://github.com/tailscale/tailscale/issues/1543)).
- If you previously enabled this repo’s “local dnsmasq upstream” integration, you may have a stale system resolver override still pointing at `127.0.0.1:5353`. Remove that override (systemd-resolved config/drop-in) when switching to the Split DNS model.

### Template knobs
Select the mode using `dnsmasq_address_all`:

- **Default (local wildcard)**: `dnsmasq_address_all=false` (default)
  - uses `templates/dnsmasq-main.conf.j2`
  - answers only for `*.{{ target_env }}.<base-domain>` suffixes
  - default port: `dnsmasq_port=5353`
- **Split-DNS nameserver (generic answer-all)**: set `dnsmasq_address_all=true`
  - uses `templates/dnsmasq-splitdns.conf.j2`
  - answers *every* query it receives with `target_ip`
  - intended to run as the DNS server behind Tailscale Split DNS (so it only receives queries for your split zones)
  - typical port: `dnsmasq_port=53`

### Manual config snippet (Split DNS nameserver)
If you want to configure the Split DNS nameserver manually (outside Ansible), the minimal config is:

```conf
interface=tailscale0
bind-dynamic
port=53

# Return the same IP for every query this server receives.
# Safe only behind suffix-based Split DNS routing.
address=/#/<TARGET_IPV4>
```

## Variables

- `target_env` - Environment name (e.g., dev, staging, prod)
- `target_ip` - IP address to resolve wildcard domains to
