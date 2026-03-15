#!/bin/sh
set -euo pipefail

vault secrets enable -path=kv -version=2 kv || true
vault auth enable kubernetes || true
vault write auth/kubernetes/config \
  kubernetes_host="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# ArgoCD policy and role from versioned files (no embedded HCL in manifest).
vault policy write argocd /vault/bootstrap/argocd.hcl
vault write auth/kubernetes/role/argocd \
  bound_service_account_names=argocd-server \
  bound_service_account_namespaces=argocd \
  policies=argocd \
  ttl=24h

echo "Vault bootstrap core config complete"
