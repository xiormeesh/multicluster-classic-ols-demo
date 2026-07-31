# Multicluster Classic OLS Demo

Multicluster troubleshooting with OpenShift Lightspeed (classic, user-initiated chat). One hub cluster queries multiple spoke clusters via a standalone MCP server with the kubeconfig provider strategy.

**Status**: work in progress — OLS and MCP server installation scripts done, registration and demo scenario pending.

## Prerequisites

- Two OpenShift 4.22+ clusters (tested with [shiftlet](https://github.com/kgordeev/shiftlet)-provisioned SNO clusters)
- `oc` CLI logged into the hub cluster
- `OPENAI_API_KEY` set in your shell environment
- Spoke cluster's kubeconfig copied to the hub host

## Quick start

Edit the environment config at the top of `setup.sh` for your cluster hostnames, IPs, and kubeconfig paths, then:

```bash
export OPENAI_API_KEY=sk-...
./setup.sh
```

The script is idempotent — it detects already-completed steps and skips them.

## What `setup.sh` does

| Step | What | Status |
|------|------|--------|
| 1 | Install OLS operator + configure OLSConfig | Done |
| 2 | Deploy standalone MCP server (kubeconfig provider) | Done |
| 3 | Register hub as "production" cluster | TODO |
| 4 | Register spoke as "staging" cluster | TODO |
| 5 | Deploy payments-api-failure scenario on both clusters | TODO |
| 6 | Break staging (roll reporting-service to buggy v1.0.2) | TODO |

## Repo structure

```
├── setup.sh                      # End-to-end setup, edit env config at top
├── manifests/
│   ├── ols/                      # OLS operator install (or install from UI)
│   │   ├── 00-namespace.yaml
│   │   ├── 01-operatorgroup.yaml
│   │   ├── 02-subscription.yaml
│   │   ├── 04-olsconfig.yaml    # Includes mcpServers + introspectionEnabled: false
│   │   └── install.sh
│   └── mcp-server/               # Standalone openshift-mcp-server
│       ├── 00-config.yaml        # ConfigMap: kubeconfig provider, core+config toolsets
│       ├── 01-deployment.yaml    # Deployment + Service (hostAliases for non-DNS clusters)
│       └── install.sh            # Creates empty kubeconfig Secret + applies manifests
└── README.md
```

## Architecture

```
Hub cluster (production)
├── OLS (lightspeed-app-server)
│   └── Connects to external MCP server via mcpServers config
├── Standalone openshift-mcp-server
│   ├── kubeconfig provider: reads merged kubeconfig from Secret
│   ├── Tools get a "context" parameter (hub, spoke, etc.)
│   └── LLM picks the right cluster per query
└── mcp-kubeconfig Secret
    └── Merged kubeconfig with per-cluster read-only SA tokens

Spoke cluster (staging)
└── No OLS workloads — hub reaches it via kube-API
```

## Limitations

- **Auth is cluster-level, not per-user**: all OLS users share a read-only ServiceAccount per cluster. Per-user RBAC requires MCE + Keycloak.
- **Metrics toolset is not multicluster-aware**: Prometheus queries always hit the hub's Thanos. Spoke troubleshooting uses core tools (pods, logs, events).
- **DNS**: cluster API hostnames must be resolvable from the MCP server pod. For non-DNS environments (e.g. libvirt), the Deployment uses `hostAliases`.
- **Kubeadmin required**: registering clusters requires kubeadmin-level access to create ServiceAccounts and ClusterRoleBindings.

## Next demo (separate repo)

- Test with MCE/Keycloak for more granular RBAC
- Use MCE as a source for importing spoke credentials via ManagedCluster CR
- Cluster-proxy for spokes whose kube-API is not accessible from outside the cluster (common enterprise scenario)
