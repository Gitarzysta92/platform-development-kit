# Host topology playbooks

The legacy `host/main.yml` entrypoint remains available for the colocated local-host workflow, but it only imports `single-node/main.yml`.

Topology playbooks in this directory compose reusable phase components from `host/components/`, so orchestrator repositories can run explicit phases against explicit inventory groups.

Available topologies:

- `single-node/main.yml` - equivalent colocated K3s server and host front door, defaulting to `localhost`.
- `thin-master-infra-edge/` - thin K3s server on `k3s_server` plus host front door on an infra/edge K3s agent in `k3s_infra`.
