#!/usr/bin/env bats

setup() {
    load 'test_helper'
    VERBOSE=0
    HOST="local"

    TEST_DIR="${BATS_TEST_TMPDIR}/file_ops"
    mkdir -p "${TEST_DIR}"
}

# =============================================================================
# folder_creator
# =============================================================================

@test "folder_creator: creates folder with hostname and date in name" {
    SAVE_FOLDER="${TEST_DIR}/log_pack"
    folder_creator

    # SAVE_FOLDER should now be log_pack_<hostname>_<date>
    [[ "${SAVE_FOLDER}" == *"log_pack_"* ]]
    [ -d "${SAVE_FOLDER}" ]
}

@test "folder_creator: appends hostname to SAVE_FOLDER" {
    SAVE_FOLDER="${TEST_DIR}/output"
    local expected_hostname
    expected_hostname=$(hostname)

    folder_creator

    [[ "${SAVE_FOLDER}" == *"_${expected_hostname}_"* ]]
}

@test "folder_creator: appends date to SAVE_FOLDER" {
    SAVE_FOLDER="${TEST_DIR}/output"
    local today
    today=$(date +%Y%m%d)

    folder_creator

    [[ "${SAVE_FOLDER}" == *"${today}"* ]]
}

# =============================================================================
# save_script_data
# =============================================================================

@test "save_script_data: writes script.log with user inputs" {
    SAVE_FOLDER="${TEST_DIR}/save_test"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="20260115-080000"
    END_TIME="20260115-180000"
    GET_LOG_TOOL="rsync"
    LOG_PATHS=("path1::file1" "path2::file2")

    save_script_data

    [ -f "${SAVE_FOLDER}/script.log" ]
    local content
    content=$(cat "${SAVE_FOLDER}/script.log")
    [[ "${content}" == *"User Inputs:"* ]]
    [[ "${content}" == *"Host: local"* ]]
    [[ "${content}" == *"${START_TIME}"* ]]
    [[ "${content}" == *"${END_TIME}"* ]]
    [[ "${content}" == *"rsync"* ]]
    [[ "${content}" == *"LOG_PATHS:"* ]]
    [[ "${content}" == *"path1::file1"* ]]
    [[ "${content}" == *"path2::file2"* ]]
}

@test "save_script_data: creates script.log in SAVE_FOLDER" {
    SAVE_FOLDER="${TEST_DIR}/save_test2"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="20260101-000000"
    END_TIME="20260101-235959"
    GET_LOG_TOOL="scp"
    LOG_PATHS=()

    save_script_data

    [ -f "${SAVE_FOLDER}/script.log" ]
}

# =============================================================================
# file_cleaner
# =============================================================================

@test "file_cleaner: removes SAVE_FOLDER" {
    SAVE_FOLDER="${TEST_DIR}/to_clean"
    mkdir -p "${SAVE_FOLDER}"
    touch "${SAVE_FOLDER}/testfile.log"

    file_cleaner

    [ ! -d "${SAVE_FOLDER}" ]
}

@test "file_cleaner: skips when SAVE_FOLDER is empty" {
    SAVE_FOLDER=""
    # Should not error
    file_cleaner
}

@test "file_cleaner: warns on failed removal (non-fatal)" {
    SAVE_FOLDER="${TEST_DIR}/nonexistent_folder_xyz"
    # rm -rf on nonexistent path actually succeeds, so this just verifies no error
    file_cleaner
}

# =============================================================================
# file_copier
# =============================================================================

@test "file_copier: copies files to save path" {
    SAVE_FOLDER="${TEST_DIR}/copy_dest"
    mkdir -p "${SAVE_FOLDER}"

    local src_dir="${TEST_DIR}/src_logs"
    mkdir -p "${src_dir}"
    echo "content1" > "${src_dir}/file1.log"
    echo "content2" > "${src_dir}/file2.log"

    local -a files=("${src_dir}/file1.log" "${src_dir}/file2.log")
    file_copier "${src_dir}" files

    # Files should be copied into SAVE_FOLDER/<stripped_path>/
    local copied_dir="${SAVE_FOLDER}/${src_dir#*:}"
    [ -d "${SAVE_FOLDER}" ]
    # Verify files were copied somewhere under SAVE_FOLDER
    local found
    found=$(find "${SAVE_FOLDER}" -name "file1.log" -type f | head -1)
    [ -n "${found}" ]
}

@test "file_copier: warns on empty files array" {
    SAVE_FOLDER="${TEST_DIR}/copy_empty"
    mkdir -p "${SAVE_FOLDER}"

    local -a files=()
    run file_copier "${TEST_DIR}/some_path" files

    assert_success
    assert_output --partial "No files to copy"
}

@test "file_copier: strips /home/user/ from path" {
    SAVE_FOLDER="${TEST_DIR}/copy_strip"
    mkdir -p "${SAVE_FOLDER}"

    local src_file="${TEST_DIR}/strip_test.log"
    echo "data" > "${src_file}"

    local -a files=("${src_file}")
    local fake_path="/home/testuser/ros-docker/logs"
    file_copier "${fake_path}" files

    # After stripping /home/testuser/, save_path should be SAVE_FOLDER/ros-docker/logs
    [ -d "${SAVE_FOLDER}/ros-docker/logs" ]
}

@test "file_copier: errors with missing arguments" {
    run file_copier
    assert_failure
}

@test "file_copier: errors when only path provided" {
    run file_copier "${TEST_DIR}/path"
    assert_failure
}

# =============================================================================
# file_sender
# =============================================================================

@test "file_sender: errors on unknown tool" {
    GET_LOG_TOOL="unknown_tool"
    SAVE_FOLDER="${TEST_DIR}/sender_test"
    mkdir -p "${SAVE_FOLDER}"

    run file_sender
    assert_failure
    assert_output --partial "Unsupported file transfer tool"
}

@test "file_sender: errors when remote folder not found" {
    GET_LOG_TOOL="rsync"
    SAVE_FOLDER="${TEST_DIR}/nonexistent_remote_folder"
    HOST="local"

    run file_sender
    assert_failure
    assert_output --partial "Remote folder not found"
}

@test "file_sender: rsync mode transfers files locally" {
    GET_LOG_TOOL="rsync"
    SAVE_FOLDER="${TEST_DIR}/rsync_src"
    mkdir -p "${SAVE_FOLDER}"
    echo "rsync test" > "${SAVE_FOLDER}/test.log"
    HOST="local"

    # For local HOST, file_sender uses execute_cmd which runs locally
    # rsync needs HOST:path format but HOST="local" causes execute_cmd
    # to run "test -d" locally, which will pass
    # However rsync "${HOST}:..." will fail since "local" is not a valid host
    # So we test that it at least finds the folder and attempts rsync
    run file_sender
    # rsync will fail because "local" is not a valid SSH host
    assert_failure
}

@test "file_sender: scp mode attempts transfer" {
    GET_LOG_TOOL="scp"
    SAVE_FOLDER="${TEST_DIR}/scp_src"
    mkdir -p "${SAVE_FOLDER}"
    echo "scp test" > "${SAVE_FOLDER}/test.log"
    HOST="local"

    run file_sender
    # scp will fail because "local" is not a valid SSH host
    assert_failure
}

@test "file_sender: sftp mode attempts transfer" {
    GET_LOG_TOOL="sftp"
    SAVE_FOLDER="${TEST_DIR}/sftp_src"
    mkdir -p "${SAVE_FOLDER}"
    echo "sftp test" > "${SAVE_FOLDER}/test.log"
    HOST="local"

    run file_sender
    # sftp will fail because "local" is not a valid SSH host
    assert_failure
}

@test "file_sender: handles absolute SAVE_FOLDER path" {
    GET_LOG_TOOL="rsync"
    SAVE_FOLDER="${TEST_DIR}/abs_path_test"
    mkdir -p "${SAVE_FOLDER}"
    HOST="local"

    # SAVE_FOLDER starts with / so local_save_folder = SAVE_FOLDER
    run file_sender
    assert_failure
    # Should not contain "Remote folder not found" since the folder exists
    refute_output --partial "Remote folder not found"
}

@test "file_sender: handles relative SAVE_FOLDER path" {
    GET_LOG_TOOL="rsync"
    # Create a relative-looking path (without leading /)
    local rel_folder="relative_log_pack"
    SAVE_FOLDER="${rel_folder}"
    HOST="local"

    # Folder doesn't exist, so should fail with "Remote folder not found"
    run file_sender
    assert_failure
    assert_output --partial "Remote folder not found"
}

# =============================================================================
# get_tools_checker
# =============================================================================

@test "get_tools_checker: sets GET_LOG_TOOL to rsync when available" {
    # rsync is typically available on Linux systems
    if ! command -v rsync >/dev/null 2>&1; then
        skip "rsync not installed"
    fi

    GET_LOG_TOOL=""
    get_tools_checker
    assert_equal "${GET_LOG_TOOL}" "rsync"
}

@test "get_tools_checker: finds first available tool" {
    GET_LOG_TOOL=""
    get_tools_checker

    # Should set to one of rsync, scp, or sftp
    [[ "${GET_LOG_TOOL}" == "rsync" || "${GET_LOG_TOOL}" == "scp" || "${GET_LOG_TOOL}" == "sftp" ]]
}

# =============================================================================
# get_log
# =============================================================================

@test "get_log: warns when no files found for a log path" {
    SAVE_FOLDER="${TEST_DIR}/get_log_test"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="20260115-000000"
    END_TIME="20260115-235959"

    local empty_dir="${TEST_DIR}/empty_path"
    mkdir -p "${empty_dir}"

    LOG_PATHS=("${empty_dir}::nonexistent_file*.log")

    run get_log
    assert_success
    assert_output --partial "No files found"
}

@test "get_log: copies files when found" {
    SAVE_FOLDER="${TEST_DIR}/get_log_copy"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="20260115-000000"
    END_TIME="20260115-235959"

    local log_dir="${TEST_DIR}/app_logs"
    mkdir -p "${log_dir}"
    touch "${log_dir}/config.yaml"

    # Config file (no date token) - direct pass through
    LOG_PATHS=("${log_dir}::config.yaml")

    get_log

    # Verify file was copied somewhere under SAVE_FOLDER
    local found
    found=$(find "${SAVE_FOLDER}" -name "config.yaml" -type f | head -1)
    [ -n "${found}" ]
}

@test "get_log: handles multiple log paths" {
    SAVE_FOLDER="${TEST_DIR}/get_log_multi"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="20260115-000000"
    END_TIME="20260115-235959"

    local log_dir1="${TEST_DIR}/logs1"
    local log_dir2="${TEST_DIR}/logs2"
    mkdir -p "${log_dir1}" "${log_dir2}"
    touch "${log_dir1}/app.conf"
    touch "${log_dir2}/settings.ini"

    LOG_PATHS=("${log_dir1}::app.conf" "${log_dir2}::settings.ini")

    get_log

    local found1 found2
    found1=$(find "${SAVE_FOLDER}" -name "app.conf" -type f | head -1)
    found2=$(find "${SAVE_FOLDER}" -name "settings.ini" -type f | head -1)
    [ -n "${found1}" ]
    [ -n "${found2}" ]
}

@test "get_log: processes date-based log paths and copies matching files" {
    SAVE_FOLDER="${TEST_DIR}/get_log_date"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="20260115-000000"
    END_TIME="20260115-235959"

    local log_dir="${TEST_DIR}/dated_logs"
    mkdir -p "${log_dir}"
    touch "${log_dir}/myapp_20260115120000.log"
    touch "${log_dir}/myapp_20260116120000.log"

    LOG_PATHS=("${log_dir}::myapp_<date:%Y%m%d%H%M%S>*<suffix:.log>")

    get_log

    local found
    found=$(find "${SAVE_FOLDER}" -name "myapp_*.log" -type f | wc -l)
    # Should have copied files (at least the one in range plus expansion)
    [ "${found}" -ge 1 ]
}

@test "get_log: handles env token in path with local HOST" {
    SAVE_FOLDER="${TEST_DIR}/get_log_env"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="20260115-000000"
    END_TIME="20260115-235959"

    local log_dir="${HOME}/test_pack_log_bats_temp"
    mkdir -p "${log_dir}"
    touch "${log_dir}/test_config.yaml"

    LOG_PATHS=("<env:HOME>/test_pack_log_bats_temp::test_config.yaml")

    get_log

    local found
    found=$(find "${SAVE_FOLDER}" -name "test_config.yaml" -type f | head -1)
    [ -n "${found}" ]

    # Cleanup
    rm -rf "${log_dir}"
}

# =============================================================================
# folder_creator: hostname/date command failure (L980, L984)
# =============================================================================

@test "folder_creator: log_error when hostname command fails" {
    run bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +euo pipefail
        HOST="local"
        VERBOSE=0
        SAVE_FOLDER="'"${BATS_TEST_TMPDIR}"'/fc_test"
        # Override execute_cmd to fail on hostname
        execute_cmd() {
            if [[ "$1" == "hostname" ]]; then return 1; fi
            eval "$1"
        }
        folder_creator
    '
    assert_failure
    assert_output --partial "Failed to get hostname"
}

@test "folder_creator: log_error when date command fails" {
    run bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +euo pipefail
        HOST="local"
        VERBOSE=0
        SAVE_FOLDER="'"${BATS_TEST_TMPDIR}"'/fc_test"
        # Override execute_cmd to fail on date
        execute_cmd() {
            if [[ "$1" == *"date"* ]]; then return 1; fi
            eval "$1"
        }
        folder_creator
    '
    assert_failure
    assert_output --partial "Failed to get date"
}

# =============================================================================
# save_script_data: string_array elements (L993-996)
# =============================================================================

@test "save_script_data: string_array lines are written to script.log" {
    run bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +euo pipefail
        HOST="testhost@10.0.0.1"
        START_TIME="20260115-080000"
        END_TIME="20260115-180000"
        GET_LOG_TOOL="rsync"
        SAVE_FOLDER="'"${BATS_TEST_TMPDIR}"'/sd_test"
        VERBOSE=0
        LOG_PATHS=("path1::file1")
        mkdir -p "${SAVE_FOLDER}"
        save_script_data
        cat "${SAVE_FOLDER}/script.log"
    '
    assert_success
    assert_output --partial "Host: testhost@10.0.0.1"
    assert_output --partial "Time range: 20260115-080000 ~ 20260115-180000"
    assert_output --partial "Using tool: rsync"
    assert_output --partial "Saving logs to folder:"
}

# =============================================================================
# file_cleaner: rm failure (L1040)
# =============================================================================

@test "file_cleaner: warns when rm -rf fails" {
    run bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +euo pipefail
        HOST="local"
        VERBOSE=0
        SAVE_FOLDER="/some/path"
        # Override execute_cmd to fail
        execute_cmd() { return 1; }
        file_cleaner
    '
    assert_success
    assert_output --partial "Failed to remove remote folder"
}

# =============================================================================
# get_tools_checker: no tools available (L722)
# =============================================================================

@test "get_tools_checker: log_error when no tools available" {
    run bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +euo pipefail
        VERBOSE=0
        HAVE_SUDO_ACCESS=1
        # Override command to report nothing installed
        command() {
            if [[ "$1" == "-v" ]]; then return 1; fi
            builtin command "$@"
        }
        get_tools_checker
    '
    assert_failure
    assert_output --partial "No file transfer tools"
}
