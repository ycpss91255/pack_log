#!/usr/bin/env bats

# =============================================================================
# Signal / SIGINT trap E2E Tests
#
# Verifies that interrupt signals during the get_log phase cleanly abort the
# script with exit code 130 and let file_cleaner remove the temporary
# SAVE_FOLDER.
#
# Regression coverage: the original trap was `trap file_cleaner SIGINT
# SIGTERM` — file_cleaner returned 0, so bash resumed execution after the
# signal instead of aborting. The fix is `trap 'file_cleaner; exit 130'`.
#
# SIGINT limitation in bats:
#   Bash ignores SIGINT in asynchronous children when job control is off
#   (which is the case in bats). The bash docs say "signals ignored upon
#   entry to the shell cannot be trapped or reset" — our wrapper inherits
#   this, so `kill -INT $pid` has no effect.
#   SIGTERM does not have this inheritance and triggers the exact same trap
#   handler, so the SIGTERM path provides equivalent coverage for the
#   handler logic. Real terminal Ctrl-C is verified manually.
# =============================================================================

setup() {
    load 'test_helper'
    WRAPPER="${BATS_TEST_TMPDIR}/sigint_wrapper.sh"
    OUTPUT_PREFIX="${BATS_TEST_TMPDIR}/save"
}

# Writes a wrapper that sources pack_log.sh (source guard keeps main from
# auto-running), overrides LOG_PATHS with a <cmd:sleep> token so get_log
# blocks, then calls main with forwarded args.
_make_wrapper() {
    cat > "${WRAPPER}" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/pack_log.sh"
LOG_PATHS=(
    "/tmp/<cmd:sleep 30>dir" "dummy*" ""
)
main "\$@"
WRAPPER
    chmod +x "${WRAPPER}"
}

@test "signal-trap: SIGTERM during get_log exits with 130 via trap handler" {
    _make_wrapper

    env -u LD_PRELOAD "${WRAPPER}" \
        -l -s 260101-0000 -e 260101-2359 \
        -o "${OUTPUT_PREFIX}" --lang en >/dev/null 2>&1 &
    local pid=$!

    # Wait until get_log is blocked on <cmd:sleep 30> (past trap install).
    sleep 1
    kill -0 "${pid}" 2>/dev/null

    kill -TERM "${pid}"

    local rc=0
    wait "${pid}" || rc=$?
    [[ "${rc}" -eq 130 ]]
}

@test "signal-trap: SIGTERM removes SAVE_FOLDER via file_cleaner" {
    _make_wrapper

    env -u LD_PRELOAD "${WRAPPER}" \
        -l -s 260101-0000 -e 260101-2359 \
        -o "${OUTPUT_PREFIX}" --lang en >/dev/null 2>&1 &
    local pid=$!

    sleep 1
    kill -TERM "${pid}"
    wait "${pid}" || true

    # SAVE_FOLDER is "${OUTPUT_PREFIX}_<hostname>_<YYMMDD-HHMMSS>" after
    # folder_creator; file_cleaner should have wiped it.
    local -a leftovers=("${OUTPUT_PREFIX}"_*)
    if [[ -e "${leftovers[0]}" ]]; then
        echo "SAVE_FOLDER was not cleaned up: ${leftovers[*]}" >&2
        false
    fi
}

@test "signal-trap: main() installs SIGINT+SIGTERM trap that exits 130" {
    # Source-level check: guard against future refactors that silently drop
    # the `exit 130` (the original regression). bats cannot reliably send
    # SIGINT to an async child (see top-of-file note), so we assert the
    # trap string is wired up correctly.
    run grep -E "trap .*file_cleaner.*exit 130.* SIGINT SIGTERM" \
        "${PROJECT_ROOT}/pack_log.sh"
    assert_success
}

@test "signal-trap: main() installs EXIT trap for spinner cleanup" {
    # Same rationale as above: verify the belt-and-suspenders EXIT trap
    # stays wired, so a crash mid-spinner cannot leak the background
    # animation process.
    run grep -E "trap spinner_stop EXIT" "${PROJECT_ROOT}/pack_log.sh"
    assert_success
}
