#!/bin/sh
set -euo pipefail

TENANT_ID="${TENANT_ID:-platform}"
TENANT_NAMESPACE="${TENANT_NAMESPACE:-platform}"
PATH_PREFIX="${PATH_PREFIX:-$TENANT_ID}"
POLICY_NAME="${POLICY_NAME:-${TENANT_ID}-vso}"
ROLE_NAME="${ROLE_NAME:-${TENANT_ID}-vso}"
VSO_SERVICE_ACCOUNT="${VSO_SERVICE_ACCOUNT:-vault-secrets-operator-controller-manager}"
POLICY_PATHS="${POLICY_PATHS:-authenticator/*,argocd/repositories/*}"
EXTRA_POLICY_PATHS="${EXTRA_POLICY_PATHS:-platform-shared-resources/keycloak/*}"
ROLE_TTL="${ROLE_TTL:-24h}"

POLICY_FILE="/tmp/${POLICY_NAME}.hcl"
: > "${POLICY_FILE}"

for REL_PATH in $(printf '%s' "${POLICY_PATHS}" | tr ',' ' '); do
  printf 'path "kv/data/%s/%s" { capabilities = ["read"] }\n' "${PATH_PREFIX}" "${REL_PATH}" >> "${POLICY_FILE}"
  printf 'path "kv/metadata/%s/%s" { capabilities = ["read"] }\n' "${PATH_PREFIX}" "${REL_PATH}" >> "${POLICY_FILE}"
done

for FULL_PATH in $(printf '%s' "${EXTRA_POLICY_PATHS}" | tr ',' ' '); do
  [ -n "${FULL_PATH}" ] || continue
  printf 'path "kv/data/%s" { capabilities = ["read"] }\n' "${FULL_PATH}" >> "${POLICY_FILE}"
  printf 'path "kv/metadata/%s" { capabilities = ["read"] }\n' "${FULL_PATH}" >> "${POLICY_FILE}"
done

vault policy write "${POLICY_NAME}" "${POLICY_FILE}"
vault write "auth/kubernetes/role/${ROLE_NAME}" \
  bound_service_account_names="${VSO_SERVICE_ACCOUNT}" \
  bound_service_account_namespaces="${TENANT_NAMESPACE}" \
  policies="${POLICY_NAME}" \
  ttl="${ROLE_TTL}"

echo "VSO authz configured for tenant '${TENANT_ID}'"
