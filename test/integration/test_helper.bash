#!/bin/bash

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
PROJECT_ROOT="$(realpath "${SCRIPT_DIR}/../..")"

# ------------------------------ BATS SETUP ------------------------------
bats_load_library "bats-support"
bats_load_library "bats-assert"
bats_load_library "bats-file"

# shellcheck disable=SC1091
source "${PROJECT_ROOT}/pack_log.sh"
set +euo pipefail

# ------------------------------ INTEGRATION ENV -------------------------
INTEGRATION_SSH_KEY="${INTEGRATION_SSH_KEY:-/root/.ssh/integration_key}"
INTEGRATION_HOST="${INTEGRATION_SSH_HOST:-testuser@sshd}"
