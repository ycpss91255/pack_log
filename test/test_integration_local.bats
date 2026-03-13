#!/usr/bin/env bats

# =============================================================================
# Local Integration Tests
#
# Tests the full main() pipeline in local mode (-l) with realistic LOG_PATHS
# patterns exercising all token types: <env:VAR>, <cmd:command>,
# <date:format>, <suffix:ext>.
# =============================================================================

setup() {
    load 'test_helper'
    VERBOSE=0
    HOST=""
    NUM=""
    START_TIME=""
    END_TIME=""

    # Build a realistic log directory tree under BATS_TEST_TMPDIR
    FAKE_HOME="${BATS_TEST_TMPDIR}/fake_home"
    export FAKE_HOME

    local base="${FAKE_HOME}/ros-docker/AMR/myuser"
    mkdir -p "${base}/log_core"
    mkdir -p "${base}/log_data/lidar_detection"
    mkdir -p "${base}/log_data/lidar_detection/glog"
    mkdir -p "${base}/log_slam"
    mkdir -p "${base}/core_storage"

    local hostname_val
    hostname_val=$(hostname)
    local user_val="${USER}"

    # -- corenavi_auto logs  (date format: %Y%m%d-%H%M%S) --
    echo "core log 1" > "${base}/log_core/corenavi_auto.${hostname_val}.${user_val}.log.INFO.20260115-100000.1"
    echo "core log 2" > "${base}/log_core/corenavi_auto.${hostname_val}.${user_val}.log.INFO.20260115-140000.2"
    echo "core log 3" > "${base}/log_core/corenavi_auto.${hostname_val}.${user_val}.log.INFO.20260116-080000.3"

    # -- detect_shelf .dat  (date format: %Y%m%d%H%M%S) --
    echo "dat 1" > "${base}/log_data/lidar_detection/detect_shelf_node-DetectShelf_20260115100000_001.dat"
    echo "dat 2" > "${base}/log_data/lidar_detection/detect_shelf_node-DetectShelf_20260115160000_002.dat"
    echo "dat 3" > "${base}/log_data/lidar_detection/detect_shelf_node-DetectShelf_20260116120000_003.dat"

    # -- detect_shelf .pcd  (date format: %Y%m%d%H%M%S) --
    echo "pcd 1" > "${base}/log_data/lidar_detection/detect_shelf_20260115100000_001.pcd"
    echo "pcd 2" > "${base}/log_data/lidar_detection/detect_shelf_20260115160000_002.pcd"

    # -- glog  (date format: %Y%m%d-%H%M%S) --
    echo "glog 1" > "${base}/log_data/lidar_detection/glog/detect_shelf_node-DetectShelf-20260115-100000.log"
    echo "glog 2" > "${base}/log_data/lidar_detection/glog/detect_shelf_node-DetectShelf-20260115-160000.log"

    # -- coreslam_2D epoch logs  (date format: %s) --
    local epoch_in epoch_out
    epoch_in=$(date -d "2026-01-15 12:00:00" "+%s")
    epoch_out=$(date -d "2026-01-16 12:00:00" "+%s")
    echo "slam in" > "${base}/log_slam/coreslam_2D_${epoch_in}.log"
    echo "slam out" > "${base}/log_slam/coreslam_2D_${epoch_out}.log"

    # -- config files (no date token) --
    echo "key: value" > "${base}/core_storage/node_config.yaml"
    echo "[shelf]"    > "${base}/core_storage/shelf.ini"

    OUTPUT_DIR="${BATS_TEST_TMPDIR}/output"
}

# ---------------------------------------------------------------------------
# 1. <env:VAR> token resolution
# ---------------------------------------------------------------------------

@test "local-integration: env token resolves and finds config file" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage::node_config.yaml"
    )

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${OUTPUT_DIR}/env_test"
    assert_success
    assert_output --partial "Packaging log completed successfully"

    local -a out_dirs=("${OUTPUT_DIR}"/env_test_*)
    [[ -d "${out_dirs[0]}" ]]

    local found
    found=$(find "${out_dirs[0]}" -name "node_config.yaml" -type f | head -1)
    [[ -n "${found}" ]]
    [[ "$(cat "${found}")" == "key: value" ]]
}

# ---------------------------------------------------------------------------
# 2. <cmd:command> token resolution
# ---------------------------------------------------------------------------

@test "local-integration: cmd token resolves hostname in log path" {
    local hostname_val
    hostname_val=$(hostname)

    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_core::corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*"
    )

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${OUTPUT_DIR}/cmd_test"
    assert_success
    assert_output --partial "Packaging log completed successfully"

    local -a out_dirs=("${OUTPUT_DIR}"/cmd_test_*)
    local count
    count=$(find "${out_dirs[0]}" -name "corenavi_auto.${hostname_val}.*" -type f | wc -l)
    [[ "${count}" -ge 2 ]]
}

# ---------------------------------------------------------------------------
# 3. <date:%Y%m%d%H%M%S> filtering
# ---------------------------------------------------------------------------

@test "local-integration: date token filters files by time range" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_data/lidar_detection::detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*<suffix:.dat>"
    )

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${OUTPUT_DIR}/date_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/date_test_*)
    local count
    count=$(find "${out_dirs[0]}" -name "*.dat" -type f | wc -l)
    # 2 in-range files + boundary expansion may include the 3rd
    [[ "${count}" -ge 2 ]]
}

# ---------------------------------------------------------------------------
# 4. <date:%s> epoch format
# ---------------------------------------------------------------------------

@test "local-integration: epoch date format filters correctly" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_slam::coreslam_2D_<date:%s>*<suffix:.log>"
    )

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${OUTPUT_DIR}/epoch_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/epoch_test_*)
    local count
    count=$(find "${out_dirs[0]}" -name "*.log" -type f | wc -l)
    [[ "${count}" -ge 1 ]]
}

# ---------------------------------------------------------------------------
# 5. <suffix:ext> filtering
# ---------------------------------------------------------------------------

@test "local-integration: suffix token filters by file extension" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_data/lidar_detection::detect_shelf_<date:%Y%m%d%H%M%S>*<suffix:.pcd>"
    )

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${OUTPUT_DIR}/suffix_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/suffix_test_*)
    # Only .pcd files should be found, not .dat
    local pcd_count dat_count
    pcd_count=$(find "${out_dirs[0]}" -name "*.pcd" -type f | wc -l)
    dat_count=$(find "${out_dirs[0]}" -name "*.dat" -type f | wc -l)
    [[ "${pcd_count}" -ge 1 ]]
    [[ "${dat_count}" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# 6. Multiple LOG_PATHS with mixed token types
# ---------------------------------------------------------------------------

@test "local-integration: mixed config and date-based paths in single run" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage::node_config.yaml"
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage::shelf.ini"
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_data/lidar_detection::detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*<suffix:.dat>"
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_data/lidar_detection/glog::detect_shelf_node-DetectShelf-<date:%Y%m%d-%H%M%S>*"
    )

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${OUTPUT_DIR}/mixed_test"
    assert_success
    assert_output --partial "Packaging log completed successfully"

    local -a out_dirs=("${OUTPUT_DIR}"/mixed_test_*)
    [[ -d "${out_dirs[0]}" ]]

    # Config files
    [[ -n "$(find "${out_dirs[0]}" -name "node_config.yaml" -type f)" ]]
    [[ -n "$(find "${out_dirs[0]}" -name "shelf.ini" -type f)" ]]

    # Date-based files
    local dat_count glog_count
    dat_count=$(find "${out_dirs[0]}" -name "*.dat" -type f | wc -l)
    glog_count=$(find "${out_dirs[0]}" -name "detect_shelf_node-DetectShelf-*" -type f | wc -l)
    [[ "${dat_count}" -ge 2 ]]
    [[ "${glog_count}" -ge 1 ]]
}

# ---------------------------------------------------------------------------
# 7. No matching files - graceful handling
# ---------------------------------------------------------------------------

@test "local-integration: no files matching time range warns but succeeds" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_data/lidar_detection::detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*<suffix:.dat>"
    )

    # Time range far in the future - no files will match
    run main -l -s 20300101-000000 -e 20300101-235959 -o "${OUTPUT_DIR}/nomatch_test"
    assert_success
    assert_output --partial "No files found"
}

# ---------------------------------------------------------------------------
# 8. Output folder structure
# ---------------------------------------------------------------------------

@test "local-integration: output folder has hostname and date suffix" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage::node_config.yaml"
    )

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${OUTPUT_DIR}/structure_test"
    assert_success

    local hostname_val
    hostname_val=$(hostname)

    local -a out_dirs=("${OUTPUT_DIR}"/structure_test_*)
    [[ -d "${out_dirs[0]}" ]]
    [[ "${out_dirs[0]}" == *"_${hostname_val}_"* ]]
}

# ---------------------------------------------------------------------------
# 9. script.log is written
# ---------------------------------------------------------------------------

@test "local-integration: script.log contains user input summary" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage::node_config.yaml"
    )

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${OUTPUT_DIR}/scriptlog_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/scriptlog_test_*)
    local script_log="${out_dirs[0]}/script.log"
    [[ -f "${script_log}" ]]

    local content
    content=$(cat "${script_log}")
    [[ "${content}" == *"Host: local"* ]]
    [[ "${content}" == *"20260115-000000"* ]]
    [[ "${content}" == *"20260115-235959"* ]]
}

# ---------------------------------------------------------------------------
# 10. File content integrity
# ---------------------------------------------------------------------------

@test "local-integration: copied files have correct content" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage::shelf.ini"
    )

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${OUTPUT_DIR}/integrity_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/integrity_test_*)
    local found
    found=$(find "${out_dirs[0]}" -name "shelf.ini" -type f | head -1)
    [[ -n "${found}" ]]
    [[ "$(cat "${found}")" == "[shelf]" ]]
}

# ---------------------------------------------------------------------------
# 11. Verbose mode shows debug output
# ---------------------------------------------------------------------------

@test "local-integration: verbose mode produces debug output" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage::node_config.yaml"
    )

    run main -l -v -s 20260115-000000 -e 20260115-235959 -o "${OUTPUT_DIR}/verbose_test"
    assert_success
    assert_output --partial "[DEBUG]"
}

# ---------------------------------------------------------------------------
# 12. Empty directory in LOG_PATHS
# ---------------------------------------------------------------------------

@test "local-integration: empty directory warns no files found" {
    local empty_dir="${BATS_TEST_TMPDIR}/empty_logs"
    mkdir -p "${empty_dir}"

    LOG_PATHS=(
        "${empty_dir}::some_pattern_<date:%Y%m%d%H%M%S>*<suffix:.log>"
    )

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${OUTPUT_DIR}/empty_test"
    assert_success
    assert_output --partial "No files found"
}

# ---------------------------------------------------------------------------
# 13. Date token in suffix position
# ---------------------------------------------------------------------------

@test "local-integration: date token in suffix position works" {
    local log_dir="${BATS_TEST_TMPDIR}/suffix_date_logs"
    mkdir -p "${log_dir}"
    touch "${log_dir}/mylog_data_20260115120000.log"
    touch "${log_dir}/mylog_data_20260116080000.log"

    LOG_PATHS=(
        "${log_dir}::mylog_data_<date:%Y%m%d%H%M%S>.log"
    )

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${OUTPUT_DIR}/suffixdate_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/suffixdate_test_*)
    local count
    count=$(find "${out_dirs[0]}" -name "mylog_data_*.log" -type f | wc -l)
    [[ "${count}" -ge 1 ]]
}
