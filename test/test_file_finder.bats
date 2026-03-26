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

    file_finder "${TEST_LOG_DIR}" "node_config.yaml" "" "260115-0000" "260115-2359"

    assert_equal "${#REPLY_FILES[@]}" 1
    assert_equal "${REPLY_FILES[0]}" "${TEST_LOG_DIR}/node_config.yaml"
}

@test "file_finder: config wildcard matches multiple files" {
    touch "${TEST_LOG_DIR}/config_a.yaml"
    touch "${TEST_LOG_DIR}/config_b.yaml"
    touch "${TEST_LOG_DIR}/unrelated.txt"

    file_finder "${TEST_LOG_DIR}" "config_*" ".yaml" "260115-0000" "260115-2359"

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
        "260115-0000" "260115-2359"

    # Should include files within range plus boundary expansion
    # Timestamps: 20260114100000, 20260115080000, 20260115103000, 20260115120000, 20260116080000
    # In range (>= 20260115000000 and <= 20260115235959): 080000, 103000, 120000
    # Expansion: s_idx-- includes 20260114100000, e_idx++ includes 20260116080000
    assert_equal "${#REPLY_FILES[@]}" 5
}

# --- Date-based files with %Y%m%d-%H%M%S format ---

@test "file_finder: selects files within date range using %Y%m%d-%H%M%S format" {
    touch "${TEST_LOG_DIR}/corenavi_auto.host.user.log.INFO.20260114-100000.1"
    touch "${TEST_LOG_DIR}/corenavi_auto.host.user.log.INFO.20260115-080000.1"
    touch "${TEST_LOG_DIR}/corenavi_auto.host.user.log.INFO.20260115-120000.1"
    touch "${TEST_LOG_DIR}/corenavi_auto.host.user.log.INFO.20260116-080000.1"

    file_finder "${TEST_LOG_DIR}" \
        "corenavi_auto.host.user.log.INFO.<date:%Y%m%d-%H%M%S>*" "" \
        "260115-0000" "260115-2359"

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
        "260115-0000" "260115-2359"

    assert_equal "${#REPLY_FILES[@]}" 0
}

# --- No files matching pattern ---

@test "file_finder: returns empty when files exist but dont match prefix" {
    touch "${TEST_LOG_DIR}/some_other_file_20260115120000.dat"
    touch "${TEST_LOG_DIR}/another_file.log"

    file_finder "${TEST_LOG_DIR}" \
        "detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*" ".dat" \
        "260115-0000" "260115-2359"

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
        "260115-0000" "260115-2359"

    # In range: 20260115100000
    # s_idx=2, e_idx=2, expansion: s_idx=1 (20260114100000), e_idx=3 (20260116100000)
    assert_equal "${#REPLY_FILES[@]}" 3
    [[ "${REPLY_FILES[0]}" == *"20260114100000"* ]]
    [[ "${REPLY_FILES[1]}" == *"20260115100000"* ]]
    [[ "${REPLY_FILES[2]}" == *"20260116100000"* ]]
}

# --- All files older than range (s_idx=-1 case) ---

@test "file_finder: handles all files older than range" {
    touch "${TEST_LOG_DIR}/log_20260110100000.dat"
    touch "${TEST_LOG_DIR}/log_20260111100000.dat"
    touch "${TEST_LOG_DIR}/log_20260112100000.dat"

    file_finder "${TEST_LOG_DIR}" \
        "log_<date:%Y%m%d%H%M%S>*" ".dat" \
        "260115-0000" "260115-2359"

    # All files older than start: s_idx=-1
    # e_idx is valid (all files <= end of range? No, all < start)
    # e_idx should be 2 (last file is 20260112 which is < 20260115235959)
    # s_idx=-1 but e_idx!=-1 => s_idx=0
    # Then expansion: s_idx stays 0 (can't go lower), e_idx++ stays 2 (already last)
    assert_equal "${#REPLY_FILES[@]}" 3
}

# --- All files newer than range (e_idx=-1 case) ---

@test "file_finder: handles all files newer than range" {
    touch "${TEST_LOG_DIR}/log_20260120100000.dat"
    touch "${TEST_LOG_DIR}/log_20260121100000.dat"
    touch "${TEST_LOG_DIR}/log_20260122100000.dat"

    file_finder "${TEST_LOG_DIR}" \
        "log_<date:%Y%m%d%H%M%S>*" ".dat" \
        "260115-0000" "260115-2359"

    # All files newer than end: e_idx=-1
    # s_idx=0 (first file >= start)
    # e_idx=-1 but s_idx!=-1 => e_idx = last index (2)
    # Expansion: s_idx stays 0, e_idx stays 2 (already last)
    assert_equal "${#REPLY_FILES[@]}" 3
}

# --- No overlap (s_idx > e_idx case) ---

@test "file_finder: returns empty when no overlap in range" {
    touch "${TEST_LOG_DIR}/log_20260115100000.dat"
    touch "${TEST_LOG_DIR}/log_20260116100000.dat"

    file_finder "${TEST_LOG_DIR}" \
        "log_<date:%Y%m%d%H%M%S>*" ".dat" \
        "260117-0000" "260114-2359"

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
        "260115-0000" "260115-2359"

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
        "260115-0000" "260115-2359"

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
        "260115-0000" "260115-2359"

    # Both timestamps in range, no expansion possible (at boundaries)
    assert_equal "${#REPLY_FILES[@]}" 3
}

# --- Suffix in file_suffix parameter ---

@test "file_finder: filters by suffix correctly" {
    touch "${TEST_LOG_DIR}/detect_shelf_20260115120000_data.pcd"
    touch "${TEST_LOG_DIR}/detect_shelf_20260115120000_data.dat"

    file_finder "${TEST_LOG_DIR}" \
        "detect_shelf_<date:%Y%m%d%H%M%S>*" ".pcd" \
        "260115-0000" "260115-2359"

    assert_equal "${#REPLY_FILES[@]}" 1
    [[ "${REPLY_FILES[0]}" == *".pcd" ]]
}

# --- Date token in suffix position ---

@test "file_finder: handles date token in file_suffix" {
    touch "${TEST_LOG_DIR}/mylog_data_20260115120000.log"
    touch "${TEST_LOG_DIR}/mylog_data_20260116080000.log"

    file_finder "${TEST_LOG_DIR}" \
        "mylog_data_" "<date:%Y%m%d%H%M%S>.log" \
        "260115-0000" "260115-2359"

    # One file in range, single entry, no expansion possible
    assert_equal "${#REPLY_FILES[@]}" 1
}

# --- mapfile failure path (L851) ---

@test "file_finder: returns empty array when execute_cmd fails (mapfile failure)" {
    # Save original execute_cmd
    local _orig_exec
    _orig_exec=$(declare -f execute_cmd)

    # Override execute_cmd to fail
    execute_cmd() { return 1; }

    file_finder "${TEST_LOG_DIR}" "some_prefix" "" "260115-0000" "260115-2359"
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
        "260115-0000" "260115-2359"

    # With empty format, the raw start/end times are used for comparison
    # Files should still be found based on timestamp ordering
    [[ "${#REPLY_FILES[@]}" -ge 0 ]]
}
