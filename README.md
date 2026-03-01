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

## Vault (cluster) — bootstrap runbook (dev / manual unseal)

This repo provides:
- Vault Helm values: `cluster/vault/values.yaml` (raft storage, UI enabled)
- Vault ingress base: `cluster/vault/ingress.yaml` (host patched by client repo overlay)
- VSO example: `cluster/vault-secrets-operator/examples/secretstore-argocd.yaml`

After deploying Vault into the cluster:

1) **Initialize** Vault (capture unseal keys + root token outside git)

```bash
kubectl -n vault exec -it vault-0 -- vault operator init
```

2) **Unseal** Vault (repeat until unsealed)

```bash
kubectl -n vault exec -it vault-0 -- vault operator unseal
```

3) **Enable KV + Kubernetes auth + create an example role**

Use the provided bootstrap job (`cluster/vault/bootstrap/vault-bootstrap-job.yaml`) as a reference for:
- enabling KV v2 at `kv`
- enabling Kubernetes auth at mount `kubernetes`
- creating policy/role for ArgoCD (`argocd-server` service account)

4) **Test VSO sync**

Create a test secret in Vault:

```bash
kubectl -n vault exec -it vault-0 -- sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200; vault kv put kv/argocd/admin username=admin password=changeme'
```

Then apply the VSO example and confirm it creates a Kubernetes `Secret` in `argocd`.

