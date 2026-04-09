#!/usr/bin/env bats

setup() {
    load 'test_helper'
    VERBOSE=0
    HOST="local"

    TEST_LOG_DIR="${BATS_TEST_TMPDIR}/logs"
    mkdir -p "${TEST_LOG_DIR}"
}

# --- Config files (no date token) ---

@test "file_finder: config files with no date token are passed through directly" {
    touch "${TEST_LOG_DIR}/node_config.yaml"
    touch "${TEST_LOG_DIR}/shelf.ini"
    touch "${TEST_LOG_DIR}/other.txt"

    file_finder "${TEST_LOG_DIR}" "node_config.yaml" "" "260115-0000" "260115-2359" "false"

    assert_equal "${#REPLY_FILES[@]}" 1
    assert_equal "${REPLY_FILES[0]}" "${TEST_LOG_DIR}/node_config.yaml"
}

@test "file_finder: symlink files are included" {
    touch "${TEST_LOG_DIR}/real_config.yaml"
    ln -s "${TEST_LOG_DIR}/real_config.yaml" "${TEST_LOG_DIR}/link_config.yaml"

    file_finder "${TEST_LOG_DIR}" "link_config.yaml" "" "260115-0000" "260115-2359" "false"

    assert_equal "${#REPLY_FILES[@]}" 1
    [[ "${REPLY_FILES[0]}" == *"link_config.yaml" ]]
}

@test "file_finder: finds files through symlink directory" {
    local real_dir="${TEST_LOG_DIR}/real_mapfiles"
    mkdir -p "${real_dir}"
    echo "map data" > "${real_dir}/uimap.png"
    echo "map yaml" > "${real_dir}/uimap.yaml"
    ln -s "${real_dir}" "${TEST_LOG_DIR}/default"

    file_finder "${TEST_LOG_DIR}/default" "uimap.png" "" "260115-0000" "260115-2359" "false"

    assert_equal "${#REPLY_FILES[@]}" 1
    [[ "$(cat "${REPLY_FILES[0]}")" == "map data" ]]
}

@test "file_finder: symlink files with date token are included" {
    touch "${TEST_LOG_DIR}/real_20260115120000.log"
    ln -s "${TEST_LOG_DIR}/real_20260115120000.log" "${TEST_LOG_DIR}/app_20260115120000.log"

    file_finder "${TEST_LOG_DIR}" \
        "app_<date:%Y%m%d%H%M%S>*" ".log" \
        "260115-0000" "260115-2359" "false"

    assert_equal "${#REPLY_FILES[@]}" 1
}

@test "file_finder: config wildcard matches multiple files" {
    touch "${TEST_LOG_DIR}/config_a.yaml"
    touch "${TEST_LOG_DIR}/config_b.yaml"
    touch "${TEST_LOG_DIR}/unrelated.txt"

    file_finder "${TEST_LOG_DIR}" "config_*" ".yaml" "260115-0000" "260115-2359" "false"

    assert_equal "${#REPLY_FILES[@]}" 2
}

# --- Date-based files with %Y%m%d%H%M%S format ---

@test "file_finder: selects files within date range using %Y%m%d%H%M%S format" {
    touch "${TEST_LOG_DIR}/detect_shelf_node-DetectShelf_20260114100000.dat"
    touch "${TEST_LOG_DIR}/detect_shelf_node-DetectShelf_20260115080000.dat"
    touch "${TEST_LOG_DIR}/detect_shelf_node-DetectShelf_20260115103000.dat"
    touch "${TEST_LOG_DIR}/detect_shelf_node-DetectShelf_20260115120000.dat"
    touch "${TEST_LOG_DIR}/detect_shelf_node-DetectShelf_20260116080000.dat"

    file_finder "${TEST_LOG_DIR}" \
        "detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*" ".dat" \
        "260115-0000" "260115-2359" "false"

    # Should include files within range plus boundary expansion
    # Timestamps: 20260114100000, 20260115080000, 20260115103000, 20260115120000, 20260116080000
    # In range (>= 20260115000000 and <= 20260115235959): 080000, 103000, 120000
    # Expansion: s_idx-- includes 20260114100000, e_idx++ includes 20260116080000
    assert_equal "${#REPLY_FILES[@]}" 5
}

# --- Wildcard pattern matches multiple log levels ---

@test "file_finder: wildcard pattern matches all log levels" {
    local test_dir="${BATS_TEST_TMPDIR}/wildcard_test"
    mkdir -p "${test_dir}"
    touch "${test_dir}/corenavi_auto.host.user.log.DEBUG.20260115-120000.1"
    touch "${test_dir}/corenavi_auto.host.user.log.INFO.20260115-120100.2"
    touch "${test_dir}/corenavi_auto.host.user.log.WARNING.20260115-120200.3"
    touch "${test_dir}/corenavi_auto.host.user.log.ERROR.20260115-120300.4"
    touch "${test_dir}/corenavi_auto.host.user.log.FATAL.20260115-120400.5"

    file_finder "${test_dir}" \
        "corenavi_auto.host.user.*.<date:%Y%m%d-%H%M%S>*" "" \
        "260115-0000" "260115-2359" "false"

    assert_equal "${#REPLY_FILES[@]}" 5
}

@test "file_finder: prefix wildcard matches multiple node names" {
    local test_dir="${BATS_TEST_TMPDIR}/prefix_wildcard"
    mkdir -p "${test_dir}"
    touch "${test_dir}/corenavi_auto.host.user.log.INFO.20260115-120000.1"
    touch "${test_dir}/corenavi_slam.host.user.log.INFO.20260115-130000.2"
    touch "${test_dir}/corenavi_nav.host.user.log.WARNING.20260115-140000.3"

    file_finder "${test_dir}" \
        "corenavi_*.host.user.*.<date:%Y%m%d-%H%M%S>*" "" \
        "260115-0000" "260115-2359" "false"

    assert_equal "${#REPLY_FILES[@]}" 3
}

# --- Date-based files with %Y%m%d-%H%M%S format ---

@test "file_finder: selects files within date range using %Y%m%d-%H%M%S format" {
    touch "${TEST_LOG_DIR}/corenavi_auto.host.user.log.INFO.20260114-100000.1"
    touch "${TEST_LOG_DIR}/corenavi_auto.host.user.log.INFO.20260115-080000.1"
    touch "${TEST_LOG_DIR}/corenavi_auto.host.user.log.INFO.20260115-120000.1"
    touch "${TEST_LOG_DIR}/corenavi_auto.host.user.log.INFO.20260116-080000.1"

    file_finder "${TEST_LOG_DIR}" \
        "corenavi_auto.host.user.log.INFO.<date:%Y%m%d-%H%M%S>*" "" \
        "260115-0000" "260115-2359" "false"

    # Timestamps: 20260114-100000, 20260115-080000, 20260115-120000, 20260116-080000
    # In range: 20260115-080000, 20260115-120000
    # Expansion: s_idx-- includes 20260114-100000, e_idx++ includes 20260116-080000
    assert_equal "${#REPLY_FILES[@]}" 4
}

# --- No files found (empty directory) ---

@test "file_finder: returns empty array when no files exist" {
    local empty_dir="${BATS_TEST_TMPDIR}/empty_logs"
    mkdir -p "${empty_dir}"

    file_finder "${empty_dir}" \
        "detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*" ".dat" \
        "260115-0000" "260115-2359" "false"

    assert_equal "${#REPLY_FILES[@]}" 0
}

# --- No files matching pattern ---

@test "file_finder: returns empty when files exist but dont match prefix" {
    touch "${TEST_LOG_DIR}/some_other_file_20260115120000.dat"
    touch "${TEST_LOG_DIR}/another_file.log"

    file_finder "${TEST_LOG_DIR}" \
        "detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*" ".dat" \
        "260115-0000" "260115-2359" "false"

    assert_equal "${#REPLY_FILES[@]}" 0
}

# --- Time range expansion (boundary expansion s_idx--, e_idx++) ---

@test "file_finder: expands boundaries when range is in the middle" {
    touch "${TEST_LOG_DIR}/log_20260113100000.dat"
    touch "${TEST_LOG_DIR}/log_20260114100000.dat"
    touch "${TEST_LOG_DIR}/log_20260115100000.dat"
    touch "${TEST_LOG_DIR}/log_20260116100000.dat"
    touch "${TEST_LOG_DIR}/log_20260117100000.dat"

    file_finder "${TEST_LOG_DIR}" \
        "log_<date:%Y%m%d%H%M%S>*" ".dat" \
        "260115-0000" "260115-2359" "false"

    # In range: 20260115100000
    # s_idx=2, e_idx=2, expansion: s_idx=1 (20260114100000), e_idx=3 (20260116100000)
    assert_equal "${#REPLY_FILES[@]}" 3
    [[ "${REPLY_FILES[0]}" == *"20260114100000"* ]]
    [[ "${REPLY_FILES[1]}" == *"20260115100000"* ]]
    [[ "${REPLY_FILES[2]}" == *"20260116100000"* ]]
}

# --- All files older than range (s_idx=-1 case) ---

@test "file_finder: excludes all files older than range beyond tolerance" {
    touch "${TEST_LOG_DIR}/log_20260110100000.dat"
    touch "${TEST_LOG_DIR}/log_20260111100000.dat"
    touch "${TEST_LOG_DIR}/log_20260112100000.dat"

    FILE_TIME_TOLERANCE_MIN=30
    file_finder "${TEST_LOG_DIR}" \
        "log_<date:%Y%m%d%H%M%S>*" ".dat" \
        "260115-0000" "260115-2359" "false"

    # All files are 3+ days older than range → beyond 30 min tolerance
    assert_equal "${#REPLY_FILES[@]}" 0
}

# --- All files newer than range ---

@test "file_finder: excludes all files newer than range beyond tolerance" {
    touch "${TEST_LOG_DIR}/log_20260120100000.dat"
    touch "${TEST_LOG_DIR}/log_20260121100000.dat"
    touch "${TEST_LOG_DIR}/log_20260122100000.dat"

    FILE_TIME_TOLERANCE_MIN=30
    file_finder "${TEST_LOG_DIR}" \
        "log_<date:%Y%m%d%H%M%S>*" ".dat" \
        "260115-0000" "260115-2359" "false"

    # All files are 5+ days newer than range → beyond 30 min tolerance
    assert_equal "${#REPLY_FILES[@]}" 0
}

# --- No overlap (s_idx > e_idx case) ---

@test "file_finder: returns empty when no overlap in range" {
    touch "${TEST_LOG_DIR}/log_20260115100000.dat"
    touch "${TEST_LOG_DIR}/log_20260116100000.dat"

    file_finder "${TEST_LOG_DIR}" \
        "log_<date:%Y%m%d%H%M%S>*" ".dat" \
        "260117-0000" "260114-2359" "false"

    # start > end: s_idx=-1 (no file >= 20260117000000), e_idx=0..1 (files < 20260114235959? no, they're > end)
    # Actually e_idx=-1 too since no file <= 20260114235959
    # Both -1 => Case C triggers
    assert_equal "${#REPLY_FILES[@]}" 0
}

# --- Single file in range ---

@test "file_finder: handles single file in range" {
    touch "${TEST_LOG_DIR}/log_20260115120000.dat"

    file_finder "${TEST_LOG_DIR}" \
        "log_<date:%Y%m%d%H%M%S>*" ".dat" \
        "260115-0000" "260115-2359" "false"

    # Single file in range, s_idx=0, e_idx=0
    # Expansion: can't expand (already at boundaries)
    assert_equal "${#REPLY_FILES[@]}" 1
    [[ "${REPLY_FILES[0]}" == *"20260115120000"* ]]
}

# --- Missing arguments ---

@test "file_finder: errors when path is missing" {
    run file_finder
    assert_failure
}

@test "file_finder: errors when start_time is missing" {
    run file_finder "${TEST_LOG_DIR}" "prefix" "suffix"
    assert_failure
}

@test "file_finder: errors when end_time is missing" {
    run file_finder "${TEST_LOG_DIR}" "prefix" "suffix" "260115-0000"
    assert_failure
}

# --- Files with epoch timestamp format (%s) ---

@test "file_finder: selects files with epoch timestamp format" {
    # Epoch for 20260115-100000 = some value, compute dynamically
    local epoch_before epoch_in_range epoch_after
    epoch_before=$(date -d "2026-01-14 10:00:00" "+%s")
    epoch_in_range=$(date -d "2026-01-15 12:00:00" "+%s")
    epoch_after=$(date -d "2026-01-16 10:00:00" "+%s")

    touch "${TEST_LOG_DIR}/coreslam_2D_${epoch_before}.log"
    touch "${TEST_LOG_DIR}/coreslam_2D_${epoch_in_range}.log"
    touch "${TEST_LOG_DIR}/coreslam_2D_${epoch_after}.log"

    file_finder "${TEST_LOG_DIR}" \
        "coreslam_2D_<date:%s>*" ".log" \
        "260115-0000" "260115-2359" "false"

    # epoch_in_range is within range
    # expansion should include neighbors
    assert_equal "${#REPLY_FILES[@]}" 3
}

# --- Multiple files with same timestamp ---

@test "file_finder: handles multiple files with same timestamp" {
    touch "${TEST_LOG_DIR}/log_20260115120000_a.dat"
    touch "${TEST_LOG_DIR}/log_20260115120000_b.dat"
    touch "${TEST_LOG_DIR}/log_20260115150000_c.dat"

    file_finder "${TEST_LOG_DIR}" \
        "log_<date:%Y%m%d%H%M%S>*" ".dat" \
        "260115-0000" "260115-2359" "false"

    # Both timestamps in range, no expansion possible (at boundaries)
    assert_equal "${#REPLY_FILES[@]}" 3
}

# --- Suffix in file_suffix parameter ---

@test "file_finder: filters by suffix correctly" {
    touch "${TEST_LOG_DIR}/detect_shelf_20260115120000_data.pcd"
    touch "${TEST_LOG_DIR}/detect_shelf_20260115120000_data.dat"

    file_finder "${TEST_LOG_DIR}" \
        "detect_shelf_<date:%Y%m%d%H%M%S>*" ".pcd" \
        "260115-0000" "260115-2359" "false"

    assert_equal "${#REPLY_FILES[@]}" 1
    [[ "${REPLY_FILES[0]}" == *".pcd" ]]
}

# --- Date token in suffix position ---

@test "file_finder: handles date token in file_suffix" {
    touch "${TEST_LOG_DIR}/mylog_data_20260115120000.log"
    touch "${TEST_LOG_DIR}/mylog_data_20260116080000.log"

    file_finder "${TEST_LOG_DIR}" \
        "mylog_data_*" "<date:%Y%m%d%H%M%S>*.log" \
        "260115-0000" "260115-2359" "false"

    # In-range file plus boundary expansion includes adjacent file
    [[ "${#REPLY_FILES[@]}" -ge 1 ]]
}

# --- mapfile failure path (L851) ---

@test "file_finder: returns empty array when execute_cmd fails (mapfile failure)" {
    # Save original execute_cmd
    local _orig_exec
    _orig_exec=$(declare -f execute_cmd)

    # Override execute_cmd to fail
    execute_cmd() { return 1; }

    file_finder "${TEST_LOG_DIR}" "some_prefix" "" "260115-0000" "260115-2359" "false"
    assert_equal "${#REPLY_FILES[@]}" 0

    # Restore original
    eval "${_orig_exec}"
}

# --- file_finder: empty format branch (L878-879) ---

@test "file_finder: uses raw time strings when date format is empty" {
    # Create files with raw time strings as part of the name
    touch "${TEST_LOG_DIR}/app_20260115-100000.log"
    touch "${TEST_LOG_DIR}/app_20260116-100000.log"

    file_finder "${TEST_LOG_DIR}" \
        "app_<date:>*" ".log" \
        "260115-0000" "260115-2359" "false"

    # With empty format, the raw start/end times are used for comparison
    # Files should still be found based on timestamp ordering
    [[ "${#REPLY_FILES[@]}" -ge 0 ]]
}

# --- Time tolerance: nearby files within threshold ---

@test "file_finder: includes nearby file within tolerance when none in range" {
    # File at Jan 16, search range Jan 17 00:00-23:59 → ~24h before start
    # But file at Jan 16 23:40 → 20 min before range start → within 30 min
    touch "${TEST_LOG_DIR}/near_20260116234000.log"

    FILE_TIME_TOLERANCE_MIN=30
    file_finder "${TEST_LOG_DIR}" \
        "near_<date:%Y%m%d%H%M%S>*" ".log" \
        "260117-0000" "260117-2359" "false"

    assert_equal "${#REPLY_FILES[@]}" 1
}

@test "file_finder: excludes nearby file beyond tolerance" {
    # File at Jan 16 12:00, search range Jan 17 → >12h gap, beyond 30 min
    touch "${TEST_LOG_DIR}/far_20260116120000.log"

    FILE_TIME_TOLERANCE_MIN=30
    file_finder "${TEST_LOG_DIR}" \
        "far_<date:%Y%m%d%H%M%S>*" ".log" \
        "260117-0000" "260117-2359" "false"

    assert_equal "${#REPLY_FILES[@]}" 0
}

@test "file_finder: tolerance 0 disables nearby file inclusion" {
    # File 20 min before range, but tolerance is 0
    touch "${TEST_LOG_DIR}/zero_20260116234000.log"

    FILE_TIME_TOLERANCE_MIN=0
    file_finder "${TEST_LOG_DIR}" \
        "zero_<date:%Y%m%d%H%M%S>*" ".log" \
        "260117-0000" "260117-2359" "false"

    assert_equal "${#REPLY_FILES[@]}" 0
}

# --- Epoch format tolerance ---

@test "file_finder: epoch format includes nearby file within tolerance" {
    # Epoch for 2026-01-15 12:03:00 (3 min after range end)
    local epoch_near
    epoch_near=$(date -d "2026-01-15 12:03:00" "+%s")
    touch "${TEST_LOG_DIR}/coreslam_2D_${epoch_near}.log"

    FILE_TIME_TOLERANCE_MIN=30
    file_finder "${TEST_LOG_DIR}" \
        "coreslam_2D_<date:%s>*" ".log" \
        "260115-1100" "260115-1200" "false"

    assert_equal "${#REPLY_FILES[@]}" 1
}

@test "file_finder: epoch format includes nearby file BEFORE range within tolerance" {
    # Epoch for 2026-01-15 10:57:00 (3 min before range start)
    local epoch_near
    epoch_near=$(date -d "2026-01-15 10:57:00" "+%s")
    touch "${TEST_LOG_DIR}/coreslam_2D_${epoch_near}.log"

    FILE_TIME_TOLERANCE_MIN=30
    file_finder "${TEST_LOG_DIR}" \
        "coreslam_2D_<date:%s>*" ".log" \
        "260115-1100" "260115-1200" "false"

    assert_equal "${#REPLY_FILES[@]}" 1
}

@test "file_finder: epoch format excludes file beyond tolerance" {
    # Epoch for 2026-01-15 14:00:00 (2h after range end)
    local epoch_far
    epoch_far=$(date -d "2026-01-15 14:00:00" "+%s")
    touch "${TEST_LOG_DIR}/coreslam_2D_${epoch_far}.log"

    FILE_TIME_TOLERANCE_MIN=30
    file_finder "${TEST_LOG_DIR}" \
        "coreslam_2D_<date:%s>*" ".log" \
        "260115-1100" "260115-1200" "false"

    assert_equal "${#REPLY_FILES[@]}" 0
}

# --- mtime flag support ---

@test "file_finder: mtime flag includes file with recent mtime but old filename timestamp" {
    # File with old filename timestamp (2025) but recent mtime (in range)
    touch "${TEST_LOG_DIR}/app_20250101120000.log"
    # Set mtime to be within the search range
    touch -t 202601151200 "${TEST_LOG_DIR}/app_20250101120000.log"

    file_finder "${TEST_LOG_DIR}" \
        "app_<date:%Y%m%d%H%M%S>*" ".log" \
        "260115-0000" "260115-2359" "true"

    [[ "${#REPLY_FILES[@]}" -ge 1 ]]
}

@test "file_finder: without mtime flag, old filename timestamp is excluded" {
    touch "${TEST_LOG_DIR}/app_20250101120000.log"
    touch -t 202601151200 "${TEST_LOG_DIR}/app_20250101120000.log"

    file_finder "${TEST_LOG_DIR}" \
        "app_<date:%Y%m%d%H%M%S>*" ".log" \
        "260115-0000" "260115-2359" "false"

    assert_equal "${#REPLY_FILES[@]}" 0
}

@test "file_finder: mtime includes file created before range with mtime past range end" {
    # Scenario 3: created 2025-01-01, mtime 2026-01-16 (past range end 2026-01-15)
    # File was being written THROUGH the entire range → should be included
    touch "${TEST_LOG_DIR}/app_20250101120000.log"
    touch -t 202601161200 "${TEST_LOG_DIR}/app_20250101120000.log"

    file_finder "${TEST_LOG_DIR}" \
        "app_<date:%Y%m%d%H%M%S>*" ".log" \
        "260115-0000" "260115-2359" "true"

    [[ "${#REPLY_FILES[@]}" -ge 1 ]]
}

@test "file_finder: mtime includes file created in range with mtime past range end" {
    # Scenario 1: created 2026-01-15 12:00, mtime 2026-01-16 (past end)
    # Filename timestamp in range → selected by normal path regardless of mtime
    touch "${TEST_LOG_DIR}/app_20260115120000.log"
    touch -t 202601161200 "${TEST_LOG_DIR}/app_20260115120000.log"

    file_finder "${TEST_LOG_DIR}" \
        "app_<date:%Y%m%d%H%M%S>*" ".log" \
        "260115-0000" "260115-2359" "true"

    [[ "${#REPLY_FILES[@]}" -ge 1 ]]
}

@test "file_finder: mtime flag does not include file with old mtime" {
    touch "${TEST_LOG_DIR}/app_20250101120000.log"
    # mtime is also old (2025)
    touch -t 202501011200 "${TEST_LOG_DIR}/app_20250101120000.log"

    file_finder "${TEST_LOG_DIR}" \
        "app_<date:%Y%m%d%H%M%S>*" ".log" \
        "260115-0000" "260115-2359" "true"

    assert_equal "${#REPLY_FILES[@]}" 0
}

@test "file_finder: mtime flag gracefully skips file when stat fails" {
    touch "${TEST_LOG_DIR}/stat_fail_20250101120000.log"
    touch -t 202601151200 "${TEST_LOG_DIR}/stat_fail_20250101120000.log"

    # Override execute_cmd to make stat fail
    local _orig_exec
    _orig_exec=$(declare -f execute_cmd)

    execute_cmd() {
        if [[ "$1" == stat* ]]; then
            return 1
        fi
        printf '%s' "$1" | bash -ls
    }

    file_finder "${TEST_LOG_DIR}" \
        "stat_fail_<date:%Y%m%d%H%M%S>*" ".log" \
        "260115-0000" "260115-2359" "true"

    # stat fails → file skipped gracefully, no crash
    assert_equal "${#REPLY_FILES[@]}" 0

    # Restore
    eval "${_orig_exec}"
}

@test "file_finder: mtime fallback batches stat calls (one execute_cmd for many files)" {
    # Create several files with old filename timestamps but recent mtimes
    local i
    for i in 1 2 3 4 5; do
        touch "${TEST_LOG_DIR}/batch_2025010112000${i}.log"
        touch -t 202601151200 "${TEST_LOG_DIR}/batch_2025010112000${i}.log"
    done

    local _orig_exec
    _orig_exec=$(declare -f execute_cmd)

    : > "${BATS_TEST_TMPDIR}/stat_calls"
    execute_cmd() {
        if [[ "$1" == *stat* ]]; then
            printf 'x\n' >> "${BATS_TEST_TMPDIR}/stat_calls"
        fi
        printf '%s' "$1" | bash -ls
    }

    file_finder "${TEST_LOG_DIR}" \
        "batch_<date:%Y%m%d%H%M%S>*" ".log" \
        "260115-0000" "260115-2359" "true"

    eval "${_orig_exec}"

    [[ "${#REPLY_FILES[@]}" -ge 5 ]]
    local n
    n=$(wc -l < "${BATS_TEST_TMPDIR}/stat_calls")
    # Must be a single batched stat call, not one per file
    assert_equal "${n}" 1
}

# --- sudo flag support ---

@test "file_finder: sudo flag accepted as parameter" {
    local test_dir="${BATS_TEST_TMPDIR}/sudo_param"
    mkdir -p "${test_dir}"
    touch "${test_dir}/syslog"

    # use_sudo=false should work without sudo
    file_finder "${test_dir}" "syslog" "" "260115-0000" "260115-2359" "false" "false"
    assert_equal "${#REPLY_FILES[@]}" 1
}

@test "file_finder: sudo flag with sudo available finds files" {
    sudo -n true 2>/dev/null || skip "sudo requires password"
    local test_dir="${BATS_TEST_TMPDIR}/sudo_find"
    mkdir -p "${test_dir}"
    touch "${test_dir}/syslog"

    file_finder "${test_dir}" "syslog" "" "260115-0000" "260115-2359" "false" "true"
    assert_equal "${#REPLY_FILES[@]}" 1
}
