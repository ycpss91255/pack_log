#!/bin/bash
#
# CI runner for pack_log.sh
#
# Usage:
#   ./ci.sh                 Run all tests (unit + integration)
#   ./ci.sh unit            Run unit tests + ShellCheck + coverage only
#   ./ci.sh integration     Run remote integration tests only
#
set -euo pipefail

# Auto-detect Docker Compose command
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
elif docker-compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
else
    echo "Error: Docker Compose is not installed."
    exit 1
fi

# Pass host UID/GID for permission fixing inside containers
export HOST_UID
HOST_UID=$(id -u)
export HOST_GID
HOST_GID=$(id -g)

run_unit() {
    echo "=== Running Unit Tests + ShellCheck + Coverage ==="
    $DOCKER_COMPOSE run --rm ci
}

run_integration() {
    echo "=== Running Remote Integration Tests ==="
    $DOCKER_COMPOSE run --rm integration
    EXIT_CODE=$?
    $DOCKER_COMPOSE down
    return "${EXIT_CODE}"
}

case "${1:-all}" in
    unit)
        run_unit
        ;;
    integration)
        run_integration
        ;;
    all)
        run_unit
        run_integration
        ;;
    *)
        echo "Usage: $0 [unit|integration|all]"
        exit 1
        ;;
esac
