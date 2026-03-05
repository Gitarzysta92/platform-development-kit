#!/bin/sh
# Vault init/unseal one-shot. Idempotent.
# Env (all optional; defaults suit platform namespace):
#   VAULT_ADDR     - Vault API URL (default: http://vault.platform.svc:8200)
#   VAULT_NS       - Kubernetes namespace for Vault and secrets (default: platform)
#   VAULT_CLI_VER  - Vault CLI version to download if missing (default: 1.17.3)
#   VAULT_WAIT_N   - Max attempts (2s each) waiting for Vault to respond (default: 60 => 120s)
set -e

VAULT_ADDR="${VAULT_ADDR:-http://vault.platform.svc:8200}"
VAULT_NS="${VAULT_NS:-platform}"
VAULT_CLI_VER="${VAULT_CLI_VER:-1.17.3}"
VAULT_WAIT_N="${VAULT_WAIT_N:-60}"
export VAULT_ADDR

# Install jq if missing (Alpine: apk, Debian: apt-get; skip if no pkg manager)
if ! command -v jq >/dev/null 2>&1; then
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache jq >/dev/null
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq jq >/dev/null
  fi
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found and no package manager (apk/apt-get). Install jq in the image or use an image that has it."
  exit 1
fi

# Install Vault CLI if missing: use .tar.gz + tar (no unzip/apt-get required)
if ! command -v vault >/dev/null 2>&1; then
  echo "Installing Vault CLI ${VAULT_CLI_VER}..."
  VAULT_TGZ="vault_${VAULT_CLI_VER}_linux_amd64.tgz"
  VAULT_URL="https://releases.hashicorp.com/vault/${VAULT_CLI_VER}/${VAULT_TGZ}"
  if command -v curl >/dev/null 2>&1; then
    curl -sSL "$VAULT_URL" -o "/tmp/${VAULT_TGZ}"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$VAULT_URL" -O "/tmp/${VAULT_TGZ}"
  else
    echo "Neither curl nor wget found. Use an image that has curl or wget."
    exit 1
  fi
  tar -xzf "/tmp/${VAULT_TGZ}" -C /tmp && mv /tmp/vault /usr/local/bin/vault && chmod +x /usr/local/bin/vault
  rm -f "/tmp/${VAULT_TGZ}"
fi

echo "Waiting for Vault at $VAULT_ADDR (max ${VAULT_WAIT_N} attempts)..."
for i in $(seq 1 "$VAULT_WAIT_N"); do
  if vault status -output=json 2>/dev/null | grep -q .; then
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
