#!/bin/bash

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
PROJECT_ROOT="$(realpath "${SCRIPT_DIR}/..")"

# ------------------------------ BATS SETUP ------------------------------
bats_load_library "bats-support"
bats_load_library "bats-assert"
bats_load_library "bats-file"

if [ -d "${BATS_TEST_DIRNAME}/lib/bats-mock" ]; then
	load "${BATS_TEST_DIRNAME}/lib/bats-mock/stub"
fi

# Source pack_log.sh (the source guard prevents main from running)
# NOTE: pack_log.sh uses 'declare' for top-level variables, which creates
# locals when sourced inside a function (bats load/setup mechanism).
# Functions are always global, but variables (HOSTS, LOG_PATHS, etc.)
# must be re-initialized in each test's setup() if needed.
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/pack_log.sh"

# Restore shell options after pack_log.sh sets -euo pipefail
set +euo pipefail
