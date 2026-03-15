# Vault bootstrap (file-based policies/scripts)

This bootstrap package configures Vault after init/unseal:

- enables `kv` (v2)
- enables `kubernetes` auth and configures it
- applies ArgoCD policy/role from versioned files
- optionally applies tenant VSO policy/role from env parameters

## Why this layout

HCL and shell logic are kept outside manifests:

- policy file: `cluster/vault/bootstrap/policies/argocd.hcl`
- scripts: `cluster/vault/bootstrap/*.sh`
- job manifest only mounts and runs these files

## Apply

```bash
kubectl apply -k cluster/vault/bootstrap
```

## Tenant-safe VSO authz parameters

The Job supports these env vars (defaults shown in manifest):

- `TENANT_ID` (e.g. `platform`)
- `TENANT_NAMESPACE` (e.g. `platform`)
- `PATH_PREFIX` (e.g. `platform` or `tenants/tenant-a`)
- `POLICY_NAME` (e.g. `platform-vso`)
- `ROLE_NAME` (e.g. `platform-vso`)
- `VSO_SERVICE_ACCOUNT` (usually `vault-secrets-operator-controller-manager`)
- `POLICY_PATHS` (comma-separated relative paths, e.g. `authenticator/*,argocd/repositories/*`)
- `ROLE_TTL` (e.g. `24h`)
- `VSO_ENABLE` (`true|false`)

To onboard another tenant, copy the Job and override names/env values so roles and policies do not collide.
