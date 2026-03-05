#!/bin/sh
set -e

VAULT_ADDR="${VAULT_ADDR:-http://vault.platform.svc:8200}"
VAULT_NS="${VAULT_NS:-platform}"
export VAULT_ADDR

# Install deps (script runs in bitnami/kubectl or similar; has apt-get)
if ! command -v jq >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y -qq jq wget unzip ca-certificates >/dev/null
fi
if ! command -v vault >/dev/null 2>&1; then
  echo "Installing Vault CLI..."
  wget -q "https://releases.hashicorp.com/vault/1.17.3/vault_1.17.3_linux_amd64.zip" -O /tmp/vault.zip
  unzip -o -q /tmp/vault.zip -d /tmp && mv /tmp/vault /usr/local/bin/vault && chmod +x /usr/local/bin/vault
  rm -f /tmp/vault.zip
fi

echo "Waiting for Vault at $VAULT_ADDR..."
for i in $(seq 1 60); do
  if vault status -output=json 2>/dev/null | grep -q .; then
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "Vault did not become ready in time"
    exit 1
  fi
  sleep 2
done

echo "Vault is reachable."

# Parse status
INITIALIZED=$(vault status -output=json 2>/dev/null | grep -o '"initialized":[^,]*' | cut -d: -f2 | tr -d ' ')
SEALED=$(vault status -output=json 2>/dev/null | grep -o '"sealed":[^,]*' | cut -d: -f2 | tr -d ' ')

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
