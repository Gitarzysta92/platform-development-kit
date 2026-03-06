FROM hashicorp/vault:1.17.3

# Toolbox image for the Vault init/unseal Job:
# - vault CLI is included via base image
# - add kubectl + jq so the job can manage secrets and parse init output

ARG KUBECTL_VERSION=v1.28.0

RUN apk add --no-cache ca-certificates curl jq && update-ca-certificates

RUN curl -sSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    chmod +x /usr/local/bin/kubectl

