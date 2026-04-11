# Vault init and unseal (automated)

This directory defines a **one-shot Job** that, when the **`vault-unseal`** Application (or full `cluster/vault` kustomization) syncs, will:

1. Wait for Vault to be reachable.
2. If Vault is **not initialized**: run `vault operator init`, store unseal keys and root token in the `vault-unseal-keys` secret, then unseal.
3. If Vault is **initialized but sealed**: read keys from `vault-unseal-keys` and unseal.
4. Ensure the `vault-root-token` secret exists (for the bootstrap job or other consumers).

The Job is **idempotent**: safe to run multiple times. It is run automatically as an Argo CD **PostSync** hook when the **`vault-unseal`** Application syncs (after Vault is deployed).

## Namespace

The base kustomization sets `namespace: platform`. Client overlays (e.g. threesixty **`vault-unseal`**) patch namespace and `VAULT_ADDR` to match where the Helm release runs (often **`platform-shared-resources`**).

## Secrets created

- **`vault-unseal-keys`**: Unseal keys 1–3 and root token (used for future unseals after restarts). **Back this up** and, for production, consider moving to a proper secret manager.
- **`vault-root-token`**: Root token under key `token` (used by the vault-bootstrap job and similar).

## Running the bootstrap job

After init/unseal, run the vault-bootstrap job (KV engine, Kubernetes auth, Argo CD policy). Ensure the bootstrap job runs in the **same namespace** as Vault (e.g. **platform**) and uses `VAULT_ADDR=http://vault.platform.svc:8200` and the `vault-root-token` secret.

## Manual run

To run the init-unseal job manually (e.g. after a new Vault install):

```bash
kubectl create job -n platform vault-init-unseal-manual --from=job/vault-init-unseal
# Or apply the kustomization and then:
kubectl delete job -n platform vault-init-unseal 2>/dev/null; kubectl apply -k ... # re-create job
```
