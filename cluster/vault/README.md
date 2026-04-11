# Vault module

This module provides base Vault resources consumed by client overlays:

- `values.yaml` (Helm values)
- `config/` — `ingress.yaml` (base ingress, host patched by client repo), `vault-connection.yaml` (VSO connection helper), `vault-auth-delegator.yaml`; referenced as `//cluster/vault/config` for overlays that must not pull `init-unseal`
- `init-unseal/` (idempotent init/unseal hook job)
- `bootstrap/` (post-unseal Vault config: auth methods, policies, roles)
- `policies/` (versioned Vault policy files, `.hcl`)

## Bootstrap usage

After Vault is unsealed and `vault-root-token` exists:

```bash
kubectl apply -k cluster/vault/bootstrap
```

See `cluster/vault/bootstrap/README.md` for tenant-safe VSO authz parameters and examples.
