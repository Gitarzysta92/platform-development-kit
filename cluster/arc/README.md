# Actions Runner Controller (ARC)

Reusable ARC definitions for client GitOps repositories.

## Layout

- `argo-application/` - Argo CD `Application` for ARC controller chart.
- `runner-scale-set-application/` - Argo CD `Application` for ARC runner scale set chart.

## Consumption pattern

Use the same split as other platform modules:

1. `argocd/...` consumes `cluster/arc/argo-application` (controller).
2. `environments/...` consumes `cluster/arc/runner-scale-set-application` and patches:
   - `spec.project`
   - `metadata.name` (recommended: `arc-runner-set-<client>`)
   - `spec.destination.namespace` (recommended: `<client>`)
   - `githubConfigUrl`
   - `githubConfigSecret.secretRef` (recommended: `arc-github-auth-<client>`)
   - `runnerScaleSetName` (recommended: `arc-runner-set-<client>`)
   - sizing (`minRunners`, `maxRunners`)

## Required Kubernetes secret

Create a secret in the runner namespace (default `arc-runners`) before syncing runner set:

```bash
kubectl -n <client> create secret generic arc-github-auth-<client> \
  --from-literal=github_token='<github_pat>'
```

PAT should have permissions according to GitHub ARC docs for your repository/org scope.

## ArgoCD OCI Helm repository note

If ArgoCD has not been configured for OCI Helm repositories yet, add GHCR chart repo with OCI enabled:

```bash
argocd repo add ghcr.io/actions/actions-runner-controller-charts \
  --type helm \
  --enable-oci
```
