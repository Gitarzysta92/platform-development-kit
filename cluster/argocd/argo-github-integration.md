# ArgoCD ↔ GitHub integration (private repositories)

When you add an ArgoCD `Application` that points at a **private** GitHub repository, ArgoCD must have credentials that allow it to run git operations (e.g. `git ls-remote`).

Typical error:

> Unable to connect HTTPS repository: authentication required: Invalid username or token. Password authentication is not supported for Git operations.

## Option A (recommended): configure in ArgoCD UI

1) Open ArgoCD UI
2) Go to **Settings → Repositories**
3) Click **Connect Repo**
4) Fill in:
   - **Repository URL**: `https://github.com/<org-or-user>/<repo>.git`
   - **Username**: your GitHub username (or `x-access-token`)
   - **Password / Token**: a GitHub Personal Access Token (PAT)
5) Click **Connect** and confirm status is **Successful**

## Option B: configure via Kubernetes secrets

This is useful for automation / bootstrapping.

### B1) Per-repo secret (tight scope)

```bash
export REPO_URL="https://github.com/<org-or-user>/<repo>.git"
export GITHUB_USERNAME="<your-username>"   # or: x-access-token
export GITHUB_TOKEN="<your-pat>"

kubectl -n argocd create secret generic <repo>-repo \
  --from-literal=type=git \
  --from-literal=url="$REPO_URL" \
  --from-literal=username="$GITHUB_USERNAME" \
  --from-literal=password="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n argocd label secret <repo>-repo \
  argocd.argoproj.io/secret-type=repository --overwrite
```

### B2) Repo credentials (covers all GitHub repos)

If you have multiple private repos under GitHub, configure a single `repo-creds` secret for the base URL:

```bash
export GITHUB_USERNAME="<your-username>"   # or: x-access-token
export GITHUB_TOKEN="<your-pat>"

kubectl -n argocd create secret generic github-repo-creds \
  --from-literal=url="https://github.com/" \
  --from-literal=username="$GITHUB_USERNAME" \
  --from-literal=password="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n argocd label secret github-repo-creds \
  argocd.argoproj.io/secret-type=repo-creds --overwrite
```

## Token requirements (GitHub)

- **Do not use your GitHub password** (GitHub removed password auth for git over HTTPS).
- **Classic PAT**: needs `repo` scope for private repositories.
- **Fine-grained PAT**: grant access to the repository and at least **Contents: Read** permission.
- If your repo is in an org with **SSO enforcement**, you may need to explicitly authorize the token for that org.

## Common pitfalls

- **URL mismatch**: ArgoCD matches credentials by URL string. Be consistent with `.../<repo>` vs `.../<repo>.git`.
- **Wrong token**: expired token or token without access to the target repo will fail `ls-remote`.
- **Multiple credential sources**: per-repo secret can override/compete with repo-creds; keep it simple.

