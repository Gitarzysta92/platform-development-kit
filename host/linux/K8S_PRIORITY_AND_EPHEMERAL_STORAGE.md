# Kubernetes Priority and Ephemeral Storage Baseline

This runbook covers two stability controls:

1. Priority classes (`platform-critical` higher, `ci-runner` lower)
2. Explicit `ephemeral-storage` requests/limits for runner pods

Use this to reduce disruption when nodes approach disk pressure.

## 1) Create PriorityClass objects

Apply once per cluster:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: platform-critical
value: 100000
globalDefault: false
description: "Higher priority for platform control workloads."
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: ci-runner
value: 1000
globalDefault: false
description: "Lower priority for CI runner workloads."
```

Apply:

```bash
kubectl apply -f priority-classes.yaml
kubectl get priorityclass
```

## 2) Assign `platform-critical` to core platform workloads

For critical Deployments/StatefulSets (for example Argo CD, ingress, DNS), set:

```yaml
spec:
  template:
    spec:
      priorityClassName: platform-critical
```

## 3) Assign `ci-runner` to ARC runner pods

In ARC runner scale set values, set pod template priority:

```yaml
template:
  spec:
    priorityClassName: ci-runner
```

## 4) Set runner `ephemeral-storage` requests/limits

In ARC runner scale set values, set container resources explicitly.

Example:

```yaml
template:
  spec:
    containers:
      - name: runner
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
            ephemeral-storage: "256Mi"
          limits:
            cpu: "1000m"
            memory: "1Gi"
            ephemeral-storage: "1Gi"
```

If using Docker-in-Docker (`containerMode.type: dind`), also define resources for dind sidecar if present in your chart version.

## 5) Validate effective settings

Check runner pod priority and resource config:

```bash
kubectl -n <runner-namespace> get pods
kubectl -n <runner-namespace> get pod <runner-pod> -o yaml | grep -E "priorityClassName|ephemeral-storage" -n
```

Check cluster events:

```bash
kubectl get events -A --sort-by=.lastTimestamp | grep -Ei "Evicted|DiskPressure|ephemeral-storage" | tail -n 40
```

## Notes

- `PriorityClass` does not prevent disk pressure; it influences which pods are evicted first under pressure.
- `ephemeral-storage` requests/limits make scheduling and eviction behavior more predictable.
- Keep this baseline together with LVM/root expansion and kubelet image-GC/eviction tuning.
