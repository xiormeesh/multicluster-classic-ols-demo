# Multicluster Classic OLS Demo

Demo repo, not a product. See [README.md](README.md) for architecture, setup instructions, and limitations.

## Key decisions (for AI agents working on this code)

- Toolsets: `core` + `config` only. Metrics toolset is not multicluster-aware (always queries hub Prometheus).
- OLSConfig has `introspectionEnabled: false` to disable the built-in MCP sidecar and use the standalone server instead.
- `hostAliases` in MCP server Deployment for DNS resolution (shiftlet clusters use `/etc/hosts`, not DNS). Computed by `install.sh` from `.env` vars.
- Demo scenario: [payments-api-failure](https://github.com/rhobs/troubleshooting-scenarios/tree/main/generic/01-payments-api-failure) from troubleshooting-scenarios repo.
- **MCP server restart required after Secret changes**: the kubeconfig file watcher uses `fsnotify` which does not detect Kubernetes Secret volume updates (symlink swaps). Always restart the MCP server pod after register/deregister.
- ServiceAccounts are created in the `default` namespace on target clusters (avoids creating `openshift-lightspeed` on spokes where OLS is not installed).

## Development

- **Run/test**: `./setup.sh` — end-to-end setup, idempotent (skips completed steps)
- **Environment config**: copy `.env.example` to `.env` and edit
- Follow the step-by-step workflow: each change is verified before committing. `setup.sh` is the integration test — run it after any change to confirm skip detection and end-to-end flow still work.
