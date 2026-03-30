#!/usr/bin/env bats

# =============================================================================
# Remote Integration Tests
#
# Tests the full main() pipeline in remote mode with an actual SSH connection
# to the sshd container. Exercises: SSH connection, remote file discovery,
# remote file_copier, and file_sender (rsync/scp/sftp).
# =============================================================================

setup() {
    load 'test_helper'
    VERBOSE=0
    HOST="${INTEGRATION_HOST}"
    NUM=""
    START_TIME=""
    END_TIME=""

    SSH_KEY="${INTEGRATION_SSH_KEY}"
    SSH_TIMEOUT=5
    SSH_OPTS=(
        -i "${SSH_KEY}"
        -o BatchMode=yes
        -o ConnectTimeout="${SSH_TIMEOUT}"
        -o NumberOfPasswordPrompts=0
        -o PreferredAuthentications=publickey
        -o StrictHostKeyChecking=no
    )

    OUTPUT_DIR="${BATS_TEST_TMPDIR}/output"

    # Remote hostname for <cmd:hostname> token tests
    REMOTE_HOSTNAME=$(execute_cmd "hostname")
    REMOTE_USER=$(execute_cmd "whoami")
}

teardown() {
    # Clean up any remote temp folders created during tests
    if [[ -n "${SAVE_FOLDER:-}" ]]; then
        execute_cmd "rm -rf ${SAVE_FOLDER}" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# 1. Basic SSH connectivity
# ---------------------------------------------------------------------------

@test "remote: SSH connection to sshd works" {
    run execute_cmd "echo hello"
    assert_success
    assert_output "hello"
}

@test "remote: can execute commands on remote host" {
    run execute_cmd "hostname"
    assert_success
    [[ -n "${output}" ]]
}

@test "remote: can resolve remote environment variables" {
    local result=""
    get_remote_value "env" "HOME" result
    [[ "${result}" == "/home/testuser" ]]
}

# ---------------------------------------------------------------------------
# 2. Full pipeline with rsync
# ---------------------------------------------------------------------------

@test "remote: full main() pipeline with rsync transfers config files" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "shelf.ini" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/rsync_config"
    assert_success
    assert_output --partial "Packaging log completed successfully"

    local -a out_dirs=("${OUTPUT_DIR}"/rsync_config_*)
    [[ -d "${out_dirs[0]}" ]]

    [[ -n "$(find "${out_dirs[0]}" -name "node_config.yaml" -type f)" ]]
    [[ -n "$(find "${out_dirs[0]}" -name "shelf.ini" -type f)" ]]
}

@test "remote: full pipeline with rsync transfers date-filtered files" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/log_data/lidar_detection" "detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*<suffix:.dat>" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/rsync_date"
    assert_success
    assert_output --partial "Packaging log completed successfully"

    local -a out_dirs=("${OUTPUT_DIR}"/rsync_date_*)

    # Verify in-range files exist and content is correct
    local f1 f2
    f1=$(find "${out_dirs[0]}" -name "*_20260115100000_*" -type f | head -1)
    f2=$(find "${out_dirs[0]}" -name "*_20260115160000_*" -type f | head -1)
    [[ -n "${f1}" ]]
    [[ -n "${f2}" ]]
    [[ "$(cat "${f1}")" == "dat 1" ]]
    [[ "$(cat "${f2}")" == "dat 2" ]]
}

# ---------------------------------------------------------------------------
# 3. Full pipeline with scp
# ---------------------------------------------------------------------------

@test "remote: full pipeline with scp transfers files" {
    # Override get_tools_checker to force scp
    get_tools_checker() { GET_LOG_TOOL="scp"; }

    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/scp_test"
    assert_success
    assert_output --partial "Packaging log completed successfully"

    local -a out_dirs=("${OUTPUT_DIR}"/scp_test_*)
    [[ -n "$(find "${out_dirs[0]}" -name "node_config.yaml" -type f)" ]]
}

# ---------------------------------------------------------------------------
# 4. Full pipeline with sftp
# ---------------------------------------------------------------------------

@test "remote: full pipeline with sftp transfers files" {
    # Override get_tools_checker to force sftp
    get_tools_checker() { GET_LOG_TOOL="sftp"; }

    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "shelf.ini" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/sftp_test"
    assert_success
    assert_output --partial "Packaging log completed successfully"

    local -a out_dirs=("${OUTPUT_DIR}"/sftp_test_*)
    [[ -n "$(find "${out_dirs[0]}" -name "shelf.ini" -type f)" ]]
}

# ---------------------------------------------------------------------------
# 5. <cmd:hostname> token resolves on remote
# ---------------------------------------------------------------------------

@test "remote: cmd token resolves remote hostname" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/log_core" "corenavi_auto.<cmd:hostname>.<cmd:whoami>.log.INFO.<date:%Y%m%d-%H%M%S>*" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/cmd_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/cmd_test_*)
    local count
    count=$(find "${out_dirs[0]}" -name "corenavi_auto.${REMOTE_HOSTNAME}.${REMOTE_USER}.*" -type f | wc -l)
    [[ "${count}" -ge 2 ]]
}

# ---------------------------------------------------------------------------
# 6. Mixed config and date-based paths
# ---------------------------------------------------------------------------

@test "remote: mixed LOG_PATHS with config and date-based entries" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
        "<env:HOME>/ros-docker/AMR/myuser/log_data/lidar_detection" "detect_shelf_<date:%Y%m%d%H%M%S>*<suffix:.pcd>" ""
        "<env:HOME>/ros-docker/AMR/myuser/log_data/lidar_detection/glog" "detect_shelf_node-DetectShelf-<date:%Y%m%d-%H%M%S>*" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/mixed_test"
    assert_success
    assert_output --partial "Packaging log completed successfully"

    local -a out_dirs=("${OUTPUT_DIR}"/mixed_test_*)

    # Config file
    [[ -n "$(find "${out_dirs[0]}" -name "node_config.yaml" -type f)" ]]
    # PCD files
    local pcd_count
    pcd_count=$(find "${out_dirs[0]}" -name "*.pcd" -type f | wc -l)
    [[ "${pcd_count}" -ge 1 ]]
    # Glog files
    local glog_count
    glog_count=$(find "${out_dirs[0]}" -name "detect_shelf_node-DetectShelf-*" -type f | wc -l)
    [[ "${glog_count}" -ge 1 ]]
}

# ---------------------------------------------------------------------------
# 7. No files in time range
# ---------------------------------------------------------------------------

@test "remote: no files in range warns but succeeds" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/log_data/lidar_detection" "detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*<suffix:.dat>" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 300101-0000 -e 300101-2359 \
        -o "${OUTPUT_DIR}/norange_test"
    assert_success
    assert_output --partial "No files found"
}

# ---------------------------------------------------------------------------
# 8. Remote folder preserved in /tmp after success
# ---------------------------------------------------------------------------

@test "remote: SAVE_FOLDER is preserved in /tmp after successful transfer" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "preserve_test"
    assert_success

    # The remote SAVE_FOLDER should still exist in /tmp
    local remote_check
    remote_check=$(execute_cmd "ls -d /tmp/preserve_test_* 2>/dev/null || echo 'not_found'")
    [[ "${remote_check}" != "not_found" ]]

    # Clean up
    execute_cmd "rm -rf /tmp/preserve_test_*" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 9. script.log on remote is transferred
# ---------------------------------------------------------------------------

@test "remote: script.log exists in transferred output" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/scriptlog_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/scriptlog_test_*)
    local script_log="${out_dirs[0]}/script.log"
    [[ -f "${script_log}" ]]

    local content
    content=$(cat "${script_log}")
    [[ "${content}" == *"Host: ${INTEGRATION_HOST}"* ]]
    [[ "${content}" == *"260115-0000"* ]]
}

# ---------------------------------------------------------------------------
# 10. File content integrity after transfer
# ---------------------------------------------------------------------------

@test "remote: transferred files have correct content" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/content_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/content_test_*)
    local found
    found=$(find "${out_dirs[0]}" -name "node_config.yaml" -type f | head -1)
    [[ -n "${found}" ]]
    [[ "$(cat "${found}")" == "node_config: test" ]]
}

# ---------------------------------------------------------------------------
# 11. Suffix token filtering on remote
# ---------------------------------------------------------------------------

@test "remote: suffix token filters only .pcd files (not .dat)" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/log_data/lidar_detection" "detect_shelf_<date:%Y%m%d%H%M%S>*<suffix:.pcd>" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/suffix_remote"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/suffix_remote_*)
    local pcd_count dat_count
    pcd_count=$(find "${out_dirs[0]}" -name "*.pcd" -type f | wc -l)
    dat_count=$(find "${out_dirs[0]}" -name "*.dat" -type f | wc -l)
    [[ "${pcd_count}" -ge 1 ]]
    [[ "${dat_count}" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# 12. False positive check: out-of-range files must NOT be transferred
# ---------------------------------------------------------------------------

@test "remote: out-of-range files are NOT transferred" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/log_core" "corenavi_auto.<cmd:hostname>.<cmd:whoami>.log.INFO.<date:%Y%m%d-%H%M%S>*" ""
    )

    # Narrow range: only 20260115-120000 ~ 20260115-160000
    # Remote has: 20260115-100000, 20260115-140000, 20260116-080000
    # With boundary expansion: should include 100000 and 140000, may include 160000
    # But 20260116-080000 should NEVER be included
    run main -u "${INTEGRATION_HOST}" \
        -s 260115-1200 -e 260115-1600 \
        -o "${OUTPUT_DIR}/falsepos_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/falsepos_test_*)
    # The 20260116 file must NOT appear in output
    local out_of_range
    out_of_range=$(find "${out_dirs[0]}" -name "*20260116*" -type f | wc -l)
    [[ "${out_of_range}" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# 13. scp transfer content verification
# ---------------------------------------------------------------------------

@test "remote: scp transfers files with correct content" {
    get_tools_checker() { GET_LOG_TOOL="scp"; }

    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "shelf.ini" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/scp_content"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/scp_content_*)
    local found
    found=$(find "${out_dirs[0]}" -name "shelf.ini" -type f | head -1)
    [[ -n "${found}" ]]
    [[ "$(cat "${found}")" == "[shelf]" ]]
}

# ---------------------------------------------------------------------------
# 14. sftp transfer content verification
# ---------------------------------------------------------------------------

@test "remote: sftp transfers files with correct content" {
    get_tools_checker() { GET_LOG_TOOL="sftp"; }

    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/sftp_content"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/sftp_content_*)
    local found
    found=$(find "${out_dirs[0]}" -name "node_config.yaml" -type f | head -1)
    [[ -n "${found}" ]]
    [[ "$(cat "${found}")" == "node_config: test" ]]
}

# ---------------------------------------------------------------------------
# 15. Epoch date format on remote
# ---------------------------------------------------------------------------

@test "remote: epoch date format filters slam logs correctly" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/log_slam" "coreslam_2D_<date:%s>*<suffix:.log>" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/epoch_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/epoch_test_*)
    local count
    count=$(find "${out_dirs[0]}" -name "coreslam_2D_*.log" -type f | wc -l)
    [[ "${count}" -ge 1 ]]

    # Verify content of the in-range file
    local found
    found=$(find "${out_dirs[0]}" -name "coreslam_2D_*.log" -type f | head -1)
    [[ -n "${found}" ]]
    [[ "$(cat "${found}")" == "slam in" ]]
}

# ---------------------------------------------------------------------------
# 16. Directory structure preservation after transfer
# ---------------------------------------------------------------------------

@test "remote: directory structure is preserved in local output" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
        "<env:HOME>/ros-docker/AMR/myuser/log_data/lidar_detection/glog" "detect_shelf_node-DetectShelf-<date:%Y%m%d-%H%M%S>*" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/dirstructure_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/dirstructure_test_*)

    # core_storage and glog should be in separate subdirectories
    local config_path glog_path
    config_path=$(find "${out_dirs[0]}" -name "node_config.yaml" -type f | head -1)
    glog_path=$(find "${out_dirs[0]}" -name "detect_shelf_node-DetectShelf-*" -type f | head -1)
    [[ -n "${config_path}" ]]
    [[ -n "${glog_path}" ]]

    # They must be in DIFFERENT subdirectories
    local config_dir glog_dir
    config_dir=$(dirname "${config_path}")
    glog_dir=$(dirname "${glog_path}")
    [[ "${config_dir}" != "${glog_dir}" ]]

    # Subdirectory names should reflect the source paths
    [[ "${config_dir}" == *"core_storage"* ]]
    [[ "${glog_dir}" == *"glog"* ]]
}

# ---------------------------------------------------------------------------
# 17. Multiple dated files: verify each file's content individually
# ---------------------------------------------------------------------------

@test "remote: each transferred dated file has correct content" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/log_data/lidar_detection/glog" "detect_shelf_node-DetectShelf-<date:%Y%m%d-%H%M%S>*" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/multi_content"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/multi_content_*)

    local f1 f2
    f1=$(find "${out_dirs[0]}" -name "*-20260115-100000*" -type f | head -1)
    f2=$(find "${out_dirs[0]}" -name "*-20260115-160000*" -type f | head -1)
    [[ -n "${f1}" ]]
    [[ -n "${f2}" ]]
    [[ "$(cat "${f1}")" == "glog 1" ]]
    [[ "$(cat "${f2}")" == "glog 2" ]]
}

# ---------------------------------------------------------------------------
# 18. %Y-%m-%d-%H-%M-%S date format (coreslam_2D .rec files)
# ---------------------------------------------------------------------------

@test "remote: Y-m-d-H-M-S date format filters .rec files correctly" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/log_slam/record" "coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*<suffix:.rec>" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/rec_test"
    assert_success
    assert_output --partial "Packaging log completed successfully"

    local -a out_dirs=("${OUTPUT_DIR}"/rec_test_*)
    local count
    count=$(find "${out_dirs[0]}" -name "coreslam_2D_*.rec" -type f | wc -l)
    [[ "${count}" -ge 1 ]]

    # Verify the in-range file content
    local found
    found=$(find "${out_dirs[0]}" -name "*2026-01-15*" -type f | head -1)
    [[ -n "${found}" ]]
    [[ "$(cat "${found}")" == "rec in" ]]

    # Out-of-range file (2026-01-16) should NOT appear
    local oor
    oor=$(find "${out_dirs[0]}" -name "*2026-01-16*" -type f | wc -l)
    [[ "${oor}" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# 19. file_copier strips /home/*/ prefix for save path
# ---------------------------------------------------------------------------

@test "remote: file_copier strips /home/ prefix from save paths" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "run_config.yaml" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/strip_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/strip_test_*)
    local found
    found=$(find "${out_dirs[0]}" -name "run_config.yaml" -type f | head -1)
    [[ -n "${found}" ]]

    # The path should NOT contain /home/testuser/ — it should be stripped
    [[ "${found}" != *"/home/testuser/"* ]]
    # But should still contain the subpath after /home/testuser/
    [[ "${found}" == *"ros-docker/AMR/myuser/core_storage"* ]]
}

# ---------------------------------------------------------------------------
# 20. Boundary expansion: all files older than query range
# ---------------------------------------------------------------------------

@test "remote: all-files-older scenario returns no files" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/log_old" "app_<date:%Y%m%d%H%M%S>*<suffix:.log>" ""
    )

    # Query range is far in the future — all files are from 2025-01-01
    run main -u "${INTEGRATION_HOST}" \
        -s 260601-0000 -e 260601-2359 \
        -o "${OUTPUT_DIR}/boundary_test"
    assert_success
    assert_output --partial "No files found"
}

# ---------------------------------------------------------------------------
# 21. execute_cmd_from_array works on remote
# ---------------------------------------------------------------------------

@test "remote: execute_cmd_from_array processes null-delimited files" {
    # Directly test execute_cmd_from_array with a simple array
    local -a test_files=(
        "/home/testuser/ros-docker/AMR/myuser/core_storage/node_config.yaml"
        "/home/testuser/ros-docker/AMR/myuser/core_storage/shelf.ini"
    )

    local result
    result=$(execute_cmd_from_array "xargs -0 -r ls -1" test_files)
    [[ "${result}" == *"node_config.yaml"* ]]
    [[ "${result}" == *"shelf.ini"* ]]
}

# ---------------------------------------------------------------------------
# 22. Symlink files are discovered and transferred
# ---------------------------------------------------------------------------

@test "remote: symlink files are discovered and transferred" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "link_config.yaml" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/symlink_remote"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/symlink_remote_*)
    local found
    found=$(find "${out_dirs[0]}" -name "link_config.yaml" \( -type f -o -type l \) | head -1)
    [[ -n "${found}" ]]
    [[ "$(cat "${found}")" == "node_config: test" ]]
}

# ---------------------------------------------------------------------------
# 23. Resolved path displayed in output
# ---------------------------------------------------------------------------

@test "remote: resolved path is shown after processing" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/resolved_remote"
    assert_success
    assert_output --partial "Resolved:"
    assert_output --partial "core_storage :: node_config.yaml"
}

# ---------------------------------------------------------------------------
# 24. Output folder path displayed at completion
# ---------------------------------------------------------------------------

@test "remote: output folder path shown at completion" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
    )

    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/outpath_remote"
    assert_success
    assert_output --partial "Output folder:"
}

# ---------------------------------------------------------------------------
# 25. Symlink directory: files found through symlink dir
# ---------------------------------------------------------------------------

@test "remote: finds files through symlink directory" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage/default"  "uimap.png" ""
        "<env:HOME>/ros-docker/AMR/myuser/core_storage/default"  "uimap.yaml" ""
    )
    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260115-2359 \
        -o "${OUTPUT_DIR}/symdir_remote"
    assert_success
    local -a out_dirs=("${OUTPUT_DIR}"/symdir_remote_*)
    [[ -n "$(find "${out_dirs[0]}" -name "uimap.png" \( -type f -o -type l \))" ]]
    [[ -n "$(find "${out_dirs[0]}" -name "uimap.yaml" \( -type f -o -type l \))" ]]
}

# ---------------------------------------------------------------------------
# 26. Cross-date folder expansion on remote
# ---------------------------------------------------------------------------

@test "remote: cross-date folders collect files from multiple days" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/log/AvoidStop_<date:%Y-%m-%d>"  "<date:%Y-%m-%d-%H.%M.%S>_*<suffix:_avoid.png>" ""
    )
    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260116-2359 \
        -o "${OUTPUT_DIR}/crossdate_remote"
    assert_success
    local -a out_dirs=("${OUTPUT_DIR}"/crossdate_remote_*)
    local count_15 count_16
    count_15=$(find "${out_dirs[0]}" -path "*AvoidStop_2026-01-15*" \( -type f -o -type l \) | wc -l)
    count_16=$(find "${out_dirs[0]}" -path "*AvoidStop_2026-01-16*" \( -type f -o -type l \) | wc -l)
    [[ "${count_15}" -ge 1 ]]
    [[ "${count_16}" -ge 1 ]]
}

# ---------------------------------------------------------------------------
# 27. Full scenario: symlink dir + cross-date + corenavi + rec
# ---------------------------------------------------------------------------

@test "remote: full scenario with symlink dir, cross-date, and all log types" {
    LOG_PATHS=(
        "<env:HOME>/ros-docker/AMR/myuser/core_storage/default"                              "uimap.png" ""
        "<env:HOME>/ros-docker/AMR/myuser/log/AvoidStop_<date:%Y-%m-%d>"                     "<date:%Y-%m-%d-%H.%M.%S>_*<suffix:_avoid.png>" ""
        "<env:HOME>/ros-docker/AMR/myuser/log_core"                                          "corenavi_auto.<cmd:hostname>.<cmd:whoami>.log.INFO.<date:%Y%m%d-%H%M%S>*" ""
        "<env:HOME>/ros-docker/AMR/myuser/log_slam/record"                                   "coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*<suffix:.rec>" ""
    )
    run main -u "${INTEGRATION_HOST}" \
        -s 260115-0000 -e 260116-2359 \
        -o "${OUTPUT_DIR}/full_scenario"
    assert_success
    assert_output --partial "Packaging log completed successfully"

    local -a out_dirs=("${OUTPUT_DIR}"/full_scenario_*)
    # uimap through symlink
    [[ -n "$(find "${out_dirs[0]}" -name "uimap.png" \( -type f -o -type l \))" ]]
    # AvoidStop from both dates
    [[ -n "$(find "${out_dirs[0]}" -path "*AvoidStop_2026-01-15*" \( -type f -o -type l \))" ]]
    [[ -n "$(find "${out_dirs[0]}" -path "*AvoidStop_2026-01-16*" \( -type f -o -type l \))" ]]
    # corenavi
    [[ -n "$(find "${out_dirs[0]}" -name "corenavi_auto.*" \( -type f -o -type l \))" ]]
    # rec files
    [[ -n "$(find "${out_dirs[0]}" -name "*.rec" \( -type f -o -type l \))" ]]
}
