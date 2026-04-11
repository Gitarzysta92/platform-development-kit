# Vault module

This module provides base Vault resources consumed by client overlays:

- `values.yaml` (Helm values)
- `vault-config/` — `ingress.yaml` (base ingress, host patched by client repo), `vault-connection.yaml` (VSO connection helper), `vault-auth-delegator.yaml`; remote URL `//cluster/vault/vault-config` (same slice as a client **`vault-config`** Application)
- `vault-unseal/` — idempotent init/unseal PostSync **Job** and RBAC; remote URL `//cluster/vault/vault-unseal` (same slice as a client **`vault-unseal`** Application)
- `bootstrap/` (post-unseal Vault config: auth methods, policies, roles)
- `policies/` (versioned Vault policy files, `.hcl`)

## Bootstrap usage

After Vault is unsealed and `vault-root-token` exists:

```bash
kubectl apply -k cluster/vault/bootstrap
```

See `cluster/vault/bootstrap/README.md` for tenant-safe VSO authz parameters and examples.
