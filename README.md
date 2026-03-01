# platform-development-kit

Reusable platform building blocks extracted from `wappsB/platform`.

This repo is intended to be consumed by *client/orchestrator* repositories (which own `argocd/` and `environments/`) via **remote Kustomize bases** and/or by running the host provisioning playbooks directly.

## Contents

- `cluster/`: Kustomize bases and Helm values for platform modules (e.g. ArgoCD config base, RabbitMQ, MinIO, OpenSearch, OPA, etc.).
- `host/`: Host provisioning (Ansible) for a single-node K3s + ingress + optional host-level reverse proxy, certs, DNS helpers, etc.
- Included cluster modules also cover a universal artifact repository via **Nexus Repository Manager OSS** (`cluster/nexus`).

## Host provisioning (Ansible)

The main playbook is `host/main.yml`.

Important inputs (all can be passed via `-e`):
- `platform_slug` (default `wapps`)
- `base_domain` (default `wapps.ai`)
- `base_domains` (optional) — list of base domains to expose (e.g. `["threesixty.dev","wapps.ai"]`). If set, host nginx + dnsmasq will generate rules for **all** of them. If omitted, it falls back to `base_domain`.
- `target_env` (default `staging`)
- `bootstrap_client_gitops` (default `false`) — legacy behavior toggle; in the target architecture the *client repo* bootstraps its ArgoCD `AppProject`/`App-of-Apps`.

### DNS options (host provisioning)
There are two common DNS patterns:

- **Local wildcard DNS (legacy / convenience)**: host runs dnsmasq locally (default `dnsmasq_port=5353`) and synthesizes `*.{{ target_env }}.<domain> -> <ip>` for each base domain.
- **Tailscale Split DNS (recommended when using tailnet DNS)**:
  - Tailscale admin console “Split DNS” routes your suffixes (e.g. `wapps.ai`, `threesixty.dev`) to a tailnet DNS server.
  - That DNS server can run dnsmasq in **answer-all** mode (no hardcoded domains in the dnsmasq config), typically on port 53.
  - See `host/dns/README.md` for the exact knobs and manual config.

## GitOps consumption (recommended)

In a client repo, reference PDK bases as remote resources, pinned to a ref:

```yaml
resources:
  - github.com/Gitarzysta92/platform-development-kit//cluster/minio?ref=main
```

Client repos should keep environment-specific overlays (domains/hosts/replicas/image tags) under `environments/**` and ArgoCD `Application` objects under `argocd/**`.

## WApps GitOps conventions (client repos)

For WApps-style client repos (e.g. `wappsB`, analogous to `threesixty-platform`), use a **single workload namespace**:

- **Namespace**
  - Deploy *all* platform modules and application workloads into the `wapps` namespace.
  - Keep Argo CD control-plane resources (Argo CD itself, `AppProject`, `Application` CRs) in the `argocd` namespace.

- **Argo CD application “tags” (labels)**
  - Add a tag label to every Argo CD `Application` (for filtering/grouping in the Argo CD UI):
    - `wapps.ai/tag: platform | backend | frontend`
  - Recommended standard labels:
    - `app.kubernetes.io/name: <app-name>`
    - `app.kubernetes.io/part-of: wapps`

- **Repository layout**
  - `argocd/applications/platform/**`: platform modules (MinIO, RabbitMQ, OpenSearch, OPA, etc.)
  - `argocd/applications/backend/**`: backend services and agents
  - `argocd/applications/frontend/**`: frontend portals/apps
  - `environments/<env>/**`: environment overlays; set `namespace: wapps` in each `kustomization.yaml` overlay (except Argo CD itself).
  - `environments/<env>/platform/namespaces-kustomization/**`: create only the `wapps` namespace.

## Shared platform namespace conventions (multi-tenant clusters)

If you plan to run **many tenants/products** in the same cluster (e.g. `wapps`, `wirtualne-biuro`, …), a common model is:

- **Namespaces**
  - `argocd`: Argo CD control-plane + `Application`/`AppProject` objects
  - `platform`: shared cluster platform modules (MinIO, RabbitMQ, OpenSearch, OPA, Vault, Nexus, cloudflared, etc.)
  - `<tenant>`: per-tenant workloads only

- **Important: disable per-module Namespace objects from PDK bases**
  - Some PDK `cluster/**` bases include a `Namespace` manifest (e.g. `cluster/minio/namespace.yaml`, `cluster/rabbitmq/namespace.yaml`, …).
  - If you want all shared platform resources in the `platform` namespace, you must **delete** those `Namespace` objects in your client repo overlay; otherwise Argo CD will keep recreating per-module namespaces.

Example overlay pattern (delete the base namespace, deploy into `platform`):

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: platform

resources:
  - github.com/Gitarzysta92/platform-development-kit//cluster/minio?ref=main

patches:
  - target:
      kind: Namespace
      name: minio
    patch: |-
      apiVersion: v1
      kind: Namespace
      metadata:
        name: minio
      $patch: delete
```

## Vault (cluster) — bootstrap runbook (dev / manual unseal)

This repo provides:
- Vault Helm values: `cluster/vault/values.yaml` (raft storage, UI enabled)
- Vault ingress base: `cluster/vault/ingress.yaml` (host patched by client repo overlay)
- VSO example: `cluster/vault-secrets-operator/examples/secretstore-argocd.yaml`

After deploying Vault into the cluster:

Set `VAULT_NAMESPACE` to the namespace where Vault is deployed (e.g. `vault` for per-module, or `platform` for shared platform).

1) **Initialize** Vault (capture unseal keys + root token outside git)

```bash
kubectl -n "$VAULT_NAMESPACE" exec -it vault-0 -- vault operator init
```

2) **Unseal** Vault (repeat until unsealed)

```bash
kubectl -n "$VAULT_NAMESPACE" exec -it vault-0 -- vault operator unseal
```

3) **Enable KV + Kubernetes auth + create an example role**

Use the provided bootstrap job (`cluster/vault/bootstrap/vault-bootstrap-job.yaml`) as a reference for:
- enabling KV v2 at `kv`
- enabling Kubernetes auth at mount `kubernetes`
- creating policy/role for ArgoCD (`argocd-server` service account)

4) **Test VSO sync**

Create a test secret in Vault:

```bash
kubectl -n "$VAULT_NAMESPACE" exec -it vault-0 -- sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200; vault kv put kv/argocd/admin username=admin password=changeme'
```

Then apply the VSO example and confirm it creates a Kubernetes `Secret` in `argocd`.

## ArgoCD ↔ GitHub integration (private repos)

If you want ArgoCD to sync from **private** GitHub repositories, ArgoCD needs a PAT-based repo connection (password auth is not supported).

See `cluster/argocd/argo-github-integration.md`.

