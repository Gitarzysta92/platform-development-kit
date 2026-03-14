# Nexus Helm Publishing Setup (SDK -> Nexus)

This document describes how to publish Helm charts from `solution-development-kit` GitHub Actions to Nexus hosted by `threesixty-platform`.

## 1) Decide publishing mode

Choose one mode and keep it consistent:

- **OCI registry (recommended first)**  
  Best fit for existing workflow that already uses `helm push` to an OCI registry.
- **Helm hosted (index.yaml repo)**  
  Works too, but requires HTTP upload flow and slightly different auth/publish logic.

## 2) Prepare Nexus

1. Ensure Nexus is reachable via ingress (example: `nexus.dev.threesixty.dev`).
2. Create a dedicated repository for charts:
   - OCI mode: create an OCI/registry repository for Helm artifacts.
   - Hosted mode: create a Helm hosted repository.
3. Create a dedicated CI user/token for publishing.
4. Grant least-privilege permissions (publish to charts repo only).

## 3) Configure GitHub Environment (solution-development-kit)

Create a GitHub Environment (example: `nexus-publish`) and store credentials there instead of plain repo secrets.

Suggested variables/secrets:

- `NEXUS_HELM_REGISTRY` (e.g. OCI URL or hosted repo URL)
- `NEXUS_HOST` (e.g. `nexus.dev.threesixty.dev`)
- `NEXUS_USERNAME`
- `NEXUS_PASSWORD` (or token)
- Optional: `NEXUS_CA_CERT` (if custom CA is required)

Optional guardrails:

- required reviewers
- branch restrictions
- wait timer for protected release flows

## 4) Pilot on one chart first (Authenticator)

Start with:

- `sdk/features/identity/applications/authenticator/provisioning/helm/authenticator`

Pilot strategy:

1. Keep current image build/push path unchanged.
2. Change only Helm chart publish destination from GHCR to Nexus (via GitHub Environment values).
3. Run pilot from `main` and verify chart appears in Nexus.
4. Validate pull/install from Helm client and/or ArgoCD.

## 5) Workflow expectations

For the SDK workflow (`.github/workflows/sdk-applications-helm.workflow.yml`):

1. Select target environment (`environment: nexus-publish`).
2. Authenticate to Nexus registry/repository.
3. `helm lint` chart.
4. `helm package` with CI versioning.
5. `helm push` package to Nexus repository.
6. Emit a clear workflow summary with:
   - chart name
   - chart version
   - app version (commit SHA)
   - target Nexus repository

## 6) Versioning rules

Current pattern in SDK (`0.1.<run_number>`, `appVersion=<sha>`) is acceptable for CI builds if:

- chart versions are monotonically increasing
- no collisions across retries/branches

If stricter release semantics are needed, move to semver tags per application and publish only on release/tag events.

## 7) Rollout after pilot

When pilot succeeds:

1. Expand matrix publishing to all SDK application charts.
2. Optionally run dual-publish (GHCR + Nexus) for a short migration window.
3. Remove GHCR chart publishing after consumers are migrated.

## 8) Verification checklist

- Nexus chart repository exists and accepts push
- GitHub Environment variables/secrets are configured
- Workflow run completes (lint/package/push)
- Chart is visible in Nexus
- Chart can be pulled and installed
- ArgoCD can resolve and deploy chart from Nexus
