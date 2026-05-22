# Tailscale Configuration for Host Base

This role joins the host to Tailscale so host-level services can be reached from the tailnet. Cluster installation, kubeconfig distribution, cluster service DNS, and application routing are owned by the client/orchestrator repo.

## What's Configured

- Tailscale installation with automatic startup
- Firewall rules for Tailscale traffic
- Hostname generation from `tailscale_hostname` or `{{ target_env }}-{{ platform_slug }}`
- Tailscale IP discovery for host DNS helper tasks

## Authentication

Set `tailscale_auth_key` as an Ansible variable or export `TAILSCALE_AUTH_KEY` in the calling environment and pass it through from the owning repo.

Manual authentication after provisioning:

```bash
sudo tailscale up --hostname="<host-name>" --accept-dns=true
```

## Optional Kubeconfig Update

The role does not modify kubeconfig by default. If a caller explicitly needs the old behavior, set:

```bash
-e configure_tailscale_kubeconfig=true
```

That option is legacy compatibility only; normal cluster access should be configured by the client/orchestrator repo.
