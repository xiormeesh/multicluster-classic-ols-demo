# Multicluster Classic OLS Demo

Demo repo, not a product. See [README.md](README.md) for architecture, setup instructions, and limitations.

## Key decisions (for AI agents working on this code)

- Toolsets: `core` + `config` only. Metrics toolset is not multicluster-aware (always queries hub Prometheus).
- OLSConfig has `introspectionEnabled: false` to disable the built-in MCP sidecar and use the standalone server instead.
- `hostAliases` in MCP server Deployment for DNS resolution (shiftlet clusters use `/etc/hosts`, not DNS).
- Demo scenario: [payments-api-failure](https://github.com/rhobs/troubleshooting-scenarios/tree/main/generic/01-payments-api-failure) from troubleshooting-scenarios repo.

## Development

- **Run/test**: `./setup.sh` — end-to-end setup, idempotent (skips completed steps)
- **Environment config**: edit the top of `setup.sh`
- Follow the step-by-step workflow: each change is verified before committing. `setup.sh` is the integration test — run it after any change to confirm skip detection and end-to-end flow still work.
