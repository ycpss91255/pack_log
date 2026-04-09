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
    mkdir -p "${base}/log/AvoidStop_2026-01-15"
    mkdir -p "${base}/log/AvoidStop_2026-01-16"
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

    # -- AvoidStop cross-date test data --
    echo "avoid 15a" > "${base}/log/AvoidStop_2026-01-15/2026-01-15-10.00.00_111_avoid.png"
    echo "avoid 15b" > "${base}/log/AvoidStop_2026-01-15/2026-01-15-14.00.00_222_avoid.png"
    echo "avoid 16a" > "${base}/log/AvoidStop_2026-01-16/2026-01-16-09.00.00_333_avoid.png"

    # -- config files (no date token) --
    echo "key: value" > "${base}/core_storage/node_config.yaml"
    echo "[shelf]"    > "${base}/core_storage/shelf.ini"

    # -- symlink directory (mapfile/default -> mapfile/) --
    mkdir -p "${base}/core_storage/mapfile"
    echo "map data" > "${base}/core_storage/mapfile/uimap.png"
    echo "map yaml" > "${base}/core_storage/mapfile/uimap.yaml"
    ln -s "${base}/core_storage/mapfile" "${base}/core_storage/default"

    # -- coreslam_2D record files --
    mkdir -p "${base}/log_slam/record"
    echo "rec 1" > "${base}/log_slam/record/coreslam_2D_2026-01-15-10-00-00.rec"
    echo "rec 2" > "${base}/log_slam/record/coreslam_2D_2026-01-15-14-00-00.rec"
    echo "rec 3" > "${base}/log_slam/record/coreslam_2D_2026-01-16-10-00-00.rec"

    OUTPUT_DIR="${BATS_TEST_TMPDIR}/output"
}

# ---------------------------------------------------------------------------
# 1. <env:VAR> token resolution
# ---------------------------------------------------------------------------

@test "local-integration: env token resolves and finds config file" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/env_test"
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
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_core" "corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/cmd_test"
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
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_data/lidar_detection" "detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*<suffix:.dat>" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/date_test"
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
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_slam" "coreslam_2D_<date:%s>*<suffix:.log>" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/epoch_test"
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
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_data/lidar_detection" "detect_shelf_<date:%Y%m%d%H%M%S>*<suffix:.pcd>" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/suffix_test"
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
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage" "shelf.ini" ""
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_data/lidar_detection" "detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*<suffix:.dat>" ""
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_data/lidar_detection/glog" "detect_shelf_node-DetectShelf-<date:%Y%m%d-%H%M%S>*" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/mixed_test"
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
    # Use a path where no files exist
    local empty_dir="${BATS_TEST_TMPDIR}/empty_logs"
    mkdir -p "${empty_dir}"

    LOG_PATHS=(
        "${empty_dir}" "nonexistent_file_*.log" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/nomatch_test"
    assert_success
    assert_output --partial "No files found"
}

# ---------------------------------------------------------------------------
# 8. Output folder structure
# ---------------------------------------------------------------------------

@test "local-integration: output folder has hostname and date suffix" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/structure_test"
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
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/scriptlog_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/scriptlog_test_*)
    local script_log="${out_dirs[0]}/script.log"
    [[ -f "${script_log}" ]]

    local content
    content=$(cat "${script_log}")
    [[ "${content}" == *"Host: local"* ]]
    [[ "${content}" == *"260115-0000"* ]]
    [[ "${content}" == *"260115-2359"* ]]
}

@test "local-integration: pack_log.log entries have ISO 8601 timestamp (lnav format)" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/ts_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/ts_test_*)
    local log_file="${out_dirs[0]}/pack_log.log"
    [[ -f "${log_file}" ]]

    # Every non-empty line must start with: YYYY-MM-DDTHH:MM:SS+ZZZZ <space>
    # This is the exact pattern that doc/lnav/formats/installed/pack_log.json parses.
    run grep -Ev '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2} ' "${log_file}"
    # grep -v should find no violating lines (exit 1 = no match = all lines conform)
    [[ "${status}" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# 10. File content integrity
# ---------------------------------------------------------------------------

@test "local-integration: copied files have correct content" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage" "shelf.ini" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/integrity_test"
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
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
    )

    run main -l -v -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/verbose_test"
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
        "${empty_dir}" "some_pattern_<date:%Y%m%d%H%M%S>*<suffix:.log>" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/empty_test"
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
        "${log_dir}" "mylog_data_*<date:%Y%m%d%H%M%S>*.log" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/suffixdate_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/suffixdate_test_*)
    local count
    count=$(find "${out_dirs[0]}" -name "mylog_data_*.log" -type f | wc -l)
    [[ "${count}" -ge 1 ]]
}

# ---------------------------------------------------------------------------
# 14. Symlink files are collected in local mode
# ---------------------------------------------------------------------------

@test "local-integration: symlink log files are collected" {
    local link_dir="${BATS_TEST_TMPDIR}/symlink_logs"
    mkdir -p "${link_dir}"
    echo "real content" > "${link_dir}/real_config.yaml"
    ln -s "${link_dir}/real_config.yaml" "${link_dir}/link_config.yaml"

    LOG_PATHS=(
        "${link_dir}" "link_config.yaml" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/symlink_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/symlink_test_*)
    local found
    found=$(find "${out_dirs[0]}" -name "link_config.yaml" \( -type f -o -type l \) | head -1)
    [[ -n "${found}" ]]
    [[ "$(cat "${found}")" == "real content" ]]
}

# ---------------------------------------------------------------------------
# 15. Output folder is under /tmp
# ---------------------------------------------------------------------------

@test "local-integration: output folder is created under /tmp" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "localtest_tmp"
    assert_success
    assert_output --partial "/tmp/localtest_tmp_"

    # Clean up
    rm -rf /tmp/localtest_tmp_*
}

# ---------------------------------------------------------------------------
# 16. Resolved path is shown in output
# ---------------------------------------------------------------------------

@test "local-integration: resolved path is displayed after processing" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage" "node_config.yaml" ""
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/resolved_test"
    assert_success
    assert_output --partial "Resolved:"
    assert_output --partial "core_storage :: node_config.yaml"
}

# ---------------------------------------------------------------------------
# 17. Cross-date folder: AvoidStop spans multiple days
# ---------------------------------------------------------------------------

@test "local-integration: cross-date folders collect files from all days" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log/AvoidStop_<date:%Y-%m-%d>"  "<date:%Y-%m-%d-%H.%M.%S>_*<suffix:_avoid.png>" ""
    )

    # Range spans Jan 15-16
    run main -l -s 260115-0000 -e 260116-2359 -o "${OUTPUT_DIR}/crossdate_test"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/crossdate_test_*)
    # Should find files from BOTH AvoidStop_2026-01-15 and AvoidStop_2026-01-16
    local count_15 count_16
    count_15=$(find "${out_dirs[0]}" -path "*AvoidStop_2026-01-15*" \( -type f -o -type l \) | wc -l)
    count_16=$(find "${out_dirs[0]}" -path "*AvoidStop_2026-01-16*" \( -type f -o -type l \) | wc -l)
    [[ "${count_15}" -ge 1 ]]
    [[ "${count_16}" -ge 1 ]]
}

# ---------------------------------------------------------------------------
# 18. Symlink directory test
# ---------------------------------------------------------------------------

@test "local-integration: finds files through symlink directory" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage/default"  "uimap.png" ""
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage/default"  "uimap.yaml" ""
    )
    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/symdir_test"
    assert_success
    local -a out_dirs=("${OUTPUT_DIR}"/symdir_test_*)
    [[ -n "$(find "${out_dirs[0]}" -name "uimap.png" \( -type f -o -type l \))" ]]
    [[ -n "$(find "${out_dirs[0]}" -name "uimap.yaml" \( -type f -o -type l \))" ]]
}

# ---------------------------------------------------------------------------
# 19. Epoch slam log test
# ---------------------------------------------------------------------------

@test "local-integration: epoch date format filters slam logs" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_slam"  "coreslam_2D_<date:%s>*<suffix:.log>" ""
    )
    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/epoch_test2"
    assert_success
    local -a out_dirs=("${OUTPUT_DIR}"/epoch_test2_*)
    local count
    count=$(find "${out_dirs[0]}" -name "coreslam_2D_*.log" \( -type f -o -type l \) | wc -l)
    [[ "${count}" -ge 1 ]]
}

# ---------------------------------------------------------------------------
# 20. Record files with %Y-%m-%d-%H-%M-%S
# ---------------------------------------------------------------------------

@test "local-integration: Y-m-d-H-M-S date format filters record files" {
    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_slam/record"  "coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*<suffix:.rec>" ""
    )
    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/rec_test"
    assert_success
    local -a out_dirs=("${OUTPUT_DIR}"/rec_test_*)
    local count
    count=$(find "${out_dirs[0]}" -name "*.rec" \( -type f -o -type l \) | wc -l)
    [[ "${count}" -ge 1 ]]
}

# ---------------------------------------------------------------------------
# 21. Full AvoidStop scenario with all path types
# ---------------------------------------------------------------------------

@test "local-integration: full AvoidStop scenario with all path types" {
    local hostname_val
    hostname_val=$(hostname)
    local user_val="${USER}"

    LOG_PATHS=(
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage/default"                              "uimap.png" ""
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/core_storage/default"                              "uimap.yaml" ""
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log/AvoidStop_<date:%Y-%m-%d>"                     "<date:%Y-%m-%d-%H.%M.%S>_*<suffix:_avoid.png>" ""
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_core"                                          "corenavi_auto.${hostname_val}.${user_val}.log.INFO.<date:%Y%m%d-%H%M%S>*" ""
        "<env:FAKE_HOME>/ros-docker/AMR/myuser/log_slam/record"                                   "coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*<suffix:.rec>" ""
    )

    # Range spans both Jan 15-16 for cross-date
    run main -l -s 260115-0000 -e 260116-2359 -o "${OUTPUT_DIR}/full_avoid"
    assert_success
    assert_output --partial "Packaging log completed successfully"

    local -a out_dirs=("${OUTPUT_DIR}"/full_avoid_*)
    # uimap through symlink dir
    [[ -n "$(find "${out_dirs[0]}" -name "uimap.png" \( -type f -o -type l \))" ]]
    # AvoidStop from both dates
    local avoid_15 avoid_16
    avoid_15=$(find "${out_dirs[0]}" -path "*AvoidStop_2026-01-15*" \( -type f -o -type l \) | wc -l)
    avoid_16=$(find "${out_dirs[0]}" -path "*AvoidStop_2026-01-16*" \( -type f -o -type l \) | wc -l)
    [[ "${avoid_15}" -ge 1 ]]
    [[ "${avoid_16}" -ge 1 ]]
    # corenavi
    [[ -n "$(find "${out_dirs[0]}" -name "corenavi_auto.*" \( -type f -o -type l \))" ]]
    # rec files
    [[ -n "$(find "${out_dirs[0]}" -name "*.rec" \( -type f -o -type l \))" ]]
}

# ---------------------------------------------------------------------------
# 22. Auto sudo for paths outside HOME
# ---------------------------------------------------------------------------

@test "local-integration: auto sudo finds files in /var/log" {
    sudo -n true 2>/dev/null || skip "sudo requires password"

    # /var/log is outside HOME → auto sudo
    LOG_PATHS=(
        "/var/log"  "syslog"  ""
    )

    run main -l -s 260101-0000 -e 260101-2359 -o "${OUTPUT_DIR}/sudo_test"
    assert_success
    assert_output --partial "sudo"
}

# ---------------------------------------------------------------------------
# 23. Auto sudo + mtime + multiple wildcards
# ---------------------------------------------------------------------------

@test "local-integration: auto sudo with mtime and wildcards" {
    sudo -n true 2>/dev/null || skip "sudo requires password"

    # Create test files in a non-HOME, non-/tmp directory
    local test_dir="/var/tmp/pack_log_sudo_test_$$"
    sudo mkdir -p "${test_dir}"
    sudo bash -c "echo 'test' > '${test_dir}/corenavi_auto.host.user.log.INFO.20250101-120000.1'"
    sudo touch -t 202601151200 "${test_dir}/corenavi_auto.host.user.log.INFO.20250101-120000.1"
    sudo bash -c "echo 'test2' > '${test_dir}/corenavi_slam.host.user.log.WARNING.20260115-130000.2'"

    LOG_PATHS=(
        "${test_dir}"  "corenavi_*.host.user.*.<date:%Y%m%d-%H%M%S>*"  "<mtime>"
    )

    run main -l -s 260115-0000 -e 260115-2359 -o "${OUTPUT_DIR}/sudo_mtime"
    assert_success

    local -a out_dirs=("${OUTPUT_DIR}"/sudo_mtime_*)
    local count
    count=$(find "${out_dirs[0]}" -name "corenavi_*" \( -type f -o -type l \) 2>/dev/null | wc -l)
    [[ "${count}" -ge 2 ]]

    # Cleanup
    sudo rm -rf "${test_dir}"
}
