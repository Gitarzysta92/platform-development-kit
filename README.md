# platform-development-kit

Reusable platform building blocks extracted from `wappsB/platform`.

This repo is intended to be consumed by *client/orchestrator* repositories (which own `argocd/` and `environments/`) via **remote Kustomize bases** and/or by running the host provisioning playbooks directly.

## Contents

- `cluster/`: Kustomize bases and Helm values for platform modules (e.g. ArgoCD config base, RabbitMQ, MinIO, OpenSearch, OPA, etc.).
- `host/`: Host provisioning (Ansible) for a single-node K3s + ingress + optional host-level reverse proxy, certs, DNS helpers, etc.

## Host provisioning (Ansible)

The main playbook is `host/main.yml`.

Important inputs (all can be passed via `-e`):
- `platform_slug` (default `wapps`)
- `base_domain` (default `wapps.ai`)
- `target_env` (default `staging`)
- `bootstrap_client_gitops` (default `false`) — legacy behavior toggle; in the target architecture the *client repo* bootstraps its ArgoCD `AppProject`/`App-of-Apps`.

## GitOps consumption (recommended)

In a client repo, reference PDK bases as remote resources, pinned to a ref:

```yaml
resources:
  - github.com/Gitarzysta92/platform-development-kit//cluster/minio?ref=main
```

Client repos should keep environment-specific overlays (domains/hosts/replicas/image tags) under `environments/**` and ArgoCD `Application` objects under `argocd/**`.

