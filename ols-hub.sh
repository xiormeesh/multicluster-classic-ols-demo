#!/bin/bash
# Multicluster OLS hub CLI.
#
# Usage:
#   ./ols-hub.sh register cluster --name <name> --kubeconfig <path> [--no-sa]
#   ./ols-hub.sh deregister cluster --name <name> --kubeconfig <path>
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage:"
    echo "  $0 register cluster --name <name> --kubeconfig <path> [--no-sa]"
    echo "  $0 deregister cluster --name <name> --kubeconfig <path>"
    exit 1
}

[[ $# -lt 2 ]] && usage

ACTION="$1"
RESOURCE="$2"
shift 2

[[ "$RESOURCE" != "cluster" ]] && { echo "Error: unknown resource '$RESOURCE'"; usage; }

case "$ACTION" in
    register)   "$DIR/manifests/cluster-registration/register.sh" "$@" ;;
    deregister) "$DIR/manifests/cluster-registration/deregister.sh" "$@" ;;
    *) echo "Error: unknown action '$ACTION'"; usage ;;
esac
