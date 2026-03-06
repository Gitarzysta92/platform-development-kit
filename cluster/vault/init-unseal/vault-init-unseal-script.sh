#!/bin/sh
# Vault init/unseal one-shot. Idempotent.
# Env (all optional; defaults suit platform namespace):
#   VAULT_ADDR     - Vault API URL (default: http://vault.platform.svc:8200)
#   VAULT_NS       - Kubernetes namespace for Vault and secrets (default: platform)
#   VAULT_WAIT_N   - Max attempts (2s each) waiting for Vault to respond (default: 60 => 120s)
set -e

VAULT_ADDR="${VAULT_ADDR:-http://vault.platform.svc:8200}"
VAULT_NS="${VAULT_NS:-platform}"
VAULT_WAIT_N="${VAULT_WAIT_N:-60}"
export VAULT_ADDR

# This job is expected to run in the custom toolbox image (vault + kubectl + jq).
for tool in vault kubectl jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool '$tool' not found in image. Use the vault-init-unseal toolbox image."
    exit 1
  fi
done

# If the Service has no ready endpoints yet (common when Vault is sealed/uninitialized),
# fall back to the Pod IP so we can initialize/unseal even while NotReady.
VAULT_POD="${VAULT_POD:-vault-0}"
POD_IP="$(kubectl get pod -n "$VAULT_NS" "$VAULT_POD" -o jsonpath='{.status.podIP}' 2>/dev/null || true)"
if [ -n "$POD_IP" ]; then
  VAULT_ADDR="http://${POD_IP}:8200"
  export VAULT_ADDR
fi

echo "Waiting for Vault at $VAULT_ADDR (max ${VAULT_WAIT_N} attempts)..."
for i in $(seq 1 "$VAULT_WAIT_N"); do
  if vault status -format=json 2>/dev/null | grep -q .; then
    break
  fi
  if [ "$i" -eq "$VAULT_WAIT_N" ]; then
    echo "Vault did not become ready in time"
    exit 1
  fi
  sleep 2
done

echo "Vault is reachable."

# Parse status
INITIALIZED=$(vault status -format=json 2>/dev/null | grep -o '"initialized":[^,]*' | cut -d: -f2 | tr -d ' ')
SEALED=$(vault status -format=json 2>/dev/null | grep -o '"sealed":[^,]*' | cut -d: -f2 | tr -d ' ')

if [ "$INITIALIZED" = "false" ]; then
  echo "Vault not initialized. Running init..."
  vault operator init -format=json > /tmp/vault-init.json
  # Vault CLI may output keys_base64 or unseal_keys_b64
  ROOT_TOKEN=$(jq -r '.root_token // empty' /tmp/vault-init.json)
  KEY_1=$(jq -r '(.keys_base64 // .unseal_keys_b64 // .keys)[0] // empty' /tmp/vault-init.json)
  KEY_2=$(jq -r '(.keys_base64 // .unseal_keys_b64 // .keys)[1] // empty' /tmp/vault-init.json)
  KEY_3=$(jq -r '(.keys_base64 // .unseal_keys_b64 // .keys)[2] // empty' /tmp/vault-init.json)
  if [ -z "$KEY_1" ] || [ -z "$KEY_2" ] || [ -z "$KEY_3" ] || [ -z "$ROOT_TOKEN" ]; then
    echo "Failed to parse init output"
    cat /tmp/vault-init.json
    exit 1
  fi
  rm -f /tmp/vault-init.json

  # Store keys in cluster secret for future unseals (e.g. after pod restart)
  kubectl create secret generic vault-unseal-keys -n "$VAULT_NS" \
    --from-literal=unseal_key_1="$KEY_1" \
    --from-literal=unseal_key_2="$KEY_2" \
    --from-literal=unseal_key_3="$KEY_3" \
    --from-literal=root_token="$ROOT_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "Stored unseal keys and root token in secret vault-unseal-keys."
fi

if [ "$SEALED" = "true" ]; then
  echo "Vault is sealed. Unsealing..."
  if [ -z "$KEY_1" ] || [ -z "$KEY_2" ] || [ -z "$KEY_3" ]; then
    echo "Reading unseal keys from secret vault-unseal-keys..."
    KEY_1=$(kubectl get secret vault-unseal-keys -n "$VAULT_NS" -o jsonpath='{.data.unseal_key_1}' | base64 -d)
    KEY_2=$(kubectl get secret vault-unseal-keys -n "$VAULT_NS" -o jsonpath='{.data.unseal_key_2}' | base64 -d)
    KEY_3=$(kubectl get secret vault-unseal-keys -n "$VAULT_NS" -o jsonpath='{.data.unseal_key_3}' | base64 -d)
    ROOT_TOKEN=$(kubectl get secret vault-unseal-keys -n "$VAULT_NS" -o jsonpath='{.data.root_token}' | base64 -d)
  fi
  vault operator unseal "$KEY_1"
  vault operator unseal "$KEY_2"
  vault operator unseal "$KEY_3"
  echo "Unseal complete."
fi

# Ensure vault-root-token exists for bootstrap job
if ! kubectl get secret vault-root-token -n "$VAULT_NS" 2>/dev/null; then
  if [ -z "$ROOT_TOKEN" ]; then
    ROOT_TOKEN=$(kubectl get secret vault-unseal-keys -n "$VAULT_NS" -o jsonpath='{.data.root_token}' | base64 -d)
  fi
  kubectl create secret generic vault-root-token -n "$VAULT_NS" --from-literal=token="$ROOT_TOKEN"
  echo "Created secret vault-root-token."
else
  echo "Secret vault-root-token already exists."
fi

echo "Vault init/unseal done."
