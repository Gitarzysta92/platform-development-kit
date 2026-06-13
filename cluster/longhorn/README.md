# Longhorn

Reusable PDK base for installing Longhorn in lab before migrating application
PVCs. Longhorn is intentionally not made the default StorageClass.

## Pieces

- `cluster/longhorn`: namespace and non-default `longhorn-rwo-2rep`
  StorageClass.
- `cluster/longhorn/argo-application`: ArgoCD `Application` for the pinned
  Longhorn Helm chart.
- `cluster/longhorn/smoke`: optional lab-only PVC smoke workload.
- `cluster/longhorn/values.yaml`: Helm values shared by the ArgoCD application.
  The chart's built-in `longhorn` StorageClass is disabled; PDK creates only
  the explicit `longhorn-rwo-2rep` lab StorageClass.

## Lab Node Label Prerequisite

Longhorn is configured with `createDefaultDiskLabeledNodes: "true"`, so it only
creates default disks on Kubernetes nodes with the Longhorn label.

Apply these labels after the infrastructure Longhorn node prep runbook passes
and before syncing the Longhorn Helm release:

```bash
kubectl label node cluster-2-worker-1 node.longhorn.io/create-default-disk=true --overwrite
kubectl label node cluster-2-worker-2 node.longhorn.io/create-default-disk=true --overwrite
kubectl label node cluster-2-worker-3 node.longhorn.io/create-default-disk=true --overwrite
```

Do not add this label to `cluster-2-master`.

PDK does not manage Kubernetes `Node` objects declaratively. These labels are a
one-time lab prerequisite and must be audited as node-label drift if nodes are
rebuilt or renamed.

## Consumption

In a client GitOps repo, consume the base and the pinned ArgoCD application:

```yaml
resources:
  - github.com/Gitarzysta92/platform-development-kit//cluster/longhorn?ref=main
  - github.com/Gitarzysta92/platform-development-kit//cluster/longhorn/argo-application?ref=main
```

Keep `cluster/longhorn/smoke` in a lab-only overlay and remove it after
validation.

`longhorn-rwo-2rep` is for first lab testing and low-risk dev workloads only.
Two replicas give each volume a second copy, but backups are still required
before real application migration.

## Validation

```bash
kubectl -n longhorn-system get pods
kubectl get storageclass
kubectl -n longhorn-system get nodes.longhorn.io
kubectl -n longhorn-system get volumes.longhorn.io
kubectl -n longhorn-smoke get pvc,pod
```

Expected:

- Longhorn pods are running.
- Longhorn node objects exist.
- Disks are schedulable on `cluster-2-worker-1..3` only.
- No default Longhorn disk is created on `cluster-2-master`.
- `longhorn-rwo-2rep` exists and is not default.
- `longhorn-smoke` PVC is bound.

Verify pod reattach without deleting the PVC:

```bash
kubectl -n longhorn-smoke exec deploy/longhorn-smoke -- tail -n 5 /data/probe.log
kubectl -n longhorn-smoke delete pod -l app=longhorn-smoke
kubectl -n longhorn-smoke rollout status deploy/longhorn-smoke
kubectl -n longhorn-smoke exec deploy/longhorn-smoke -- tail -n 5 /data/probe.log
```

The log file must survive pod recreation.

## Migration Rules

Do not migrate application PVCs as part of the initial Longhorn install. For
each later application migration:

1. Create a new Longhorn-backed PVC.
2. Stop writes to the old workload.
3. Copy data from the old local-path PVC to the new Longhorn PVC.
4. Update the application chart values to use the Longhorn PVC.
5. Sync one app at a time.
6. Verify application-level health.
7. Keep rollback notes for restoring the old PVC path.

Do not change the cluster default StorageClass until important workloads are
explicitly migrated and a backup policy is in place.

## Before Increasing Replicas

Before moving lab or dev to two or three replicas, validate:

- Available Longhorn capacity on each prepared worker.
- Replica placement across Proxmox failure domains.
- Network performance between Proxmox hosts.
