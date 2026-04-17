#!/usr/bin/env bats

setup() {
    load 'test_helper'
    VERBOSE=0
    HOST="local"
    TRANSFER_MAX_RETRIES=3
    TRANSFER_RETRY_DELAY=0
    TRANSFER_SIZE_WARN_MB=300
    BANDWIDTH_LIMIT=0

    TEST_DIR="${BATS_TEST_TMPDIR}/file_ops"
    mkdir -p "${TEST_DIR}"
}

# =============================================================================
# folder_creator
# =============================================================================

@test "folder_creator: creates folder under /tmp when path is relative" {
    SAVE_FOLDER="test_output"
    folder_creator

    [[ "${SAVE_FOLDER}" == /tmp/test_output_* ]]
    [ -d "${SAVE_FOLDER}" ]
    rm -rf "${SAVE_FOLDER}"
}

@test "folder_creator: keeps absolute path as-is without adding /tmp prefix" {
    SAVE_FOLDER="${TEST_DIR}/abs_output"
    folder_creator

    # Should start with the original absolute path, not /tmp/<original>
    [[ "${SAVE_FOLDER}" == "${TEST_DIR}/abs_output_"* ]]
    [[ "${SAVE_FOLDER}" != "/tmp/${TEST_DIR}/"* ]]
    [ -d "${SAVE_FOLDER}" ]
}

@test "folder_creator: uses hostname for local mode" {
    HOST="local"
    NUM=""
    SAVE_FOLDER="${TEST_DIR}/output"
    local expected_hostname
    expected_hostname=$(hostname)

    folder_creator

    [[ "${SAVE_FOLDER}" == *"_${expected_hostname}_"* ]]
}

@test "folder_creator: uses hostname when NUM is empty" {
    HOST="local"
    NUM=""
    SAVE_FOLDER="${TEST_DIR}/output_uh"
    local expected_hostname
    expected_hostname=$(hostname)

    folder_creator

    [[ "${SAVE_FOLDER}" == *"_${expected_hostname}_"* ]]
}

@test "folder_creator: uses HOSTS display name for -n mode" {
    HOST="local"
    NUM="1"
    SAVE_FOLDER="${TEST_DIR}/output_n"

    local expected_name="${HOSTS[0]%%::*}"
    folder_creator

    [[ "${SAVE_FOLDER}" == *"_${expected_name}_"* ]]
}

@test "folder_creator: log_error when remote hostname command fails" {
    HOST="fake@remote"
    NUM=""
    SAVE_FOLDER="${TEST_DIR}/output_hn_fail"
    execute_cmd() {
        [[ "$1" == "hostname" ]] && return 1
        return 0
    }
    run folder_creator
    assert_failure
    assert_output --partial "Failed to get hostname/date"
}

@test "folder_creator: log_error when remote date command fails" {
    HOST="fake@remote"
    NUM=""
    SAVE_FOLDER="${TEST_DIR}/output_dt_fail"
    execute_cmd() {
        [[ "$1" == "hostname" ]] && { echo "fakehost"; return 0; }
        [[ "$1" == *"date"* ]] && return 1
        return 0
    }
    run folder_creator
    assert_failure
    assert_output --partial "Failed to get hostname/date"
}

@test "folder_creator: appends date with 2-digit year to SAVE_FOLDER" {
    SAVE_FOLDER="${TEST_DIR}/output"
    local today_2digit today_4digit
    today_2digit=$(date +%y%m%d)
    today_4digit=$(date +%Y%m%d)

    folder_creator

    # Must contain 2-digit year format, not 4-digit year format
    [[ "${SAVE_FOLDER}" == *"_${today_2digit}-"* ]]
    [[ "${SAVE_FOLDER}" != *"_${today_4digit}-"* ]]
}

# =============================================================================
# save_script_data
# =============================================================================

@test "save_script_data: writes script.log with user inputs" {
    SAVE_FOLDER="${TEST_DIR}/save_test"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260115-0800"
    END_TIME="260115-1800"
    GET_LOG_TOOL="rsync"
    LOG_PATHS=("path1" "file1" "" "path2" "file2" "")

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
    [[ "${content}" == *"path1"* ]]
    [[ "${content}" == *"file1"* ]]
    [[ "${content}" == *"path2"* ]]
    [[ "${content}" == *"file2"* ]]
}

@test "save_script_data: creates script.log in SAVE_FOLDER" {
    SAVE_FOLDER="${TEST_DIR}/save_test2"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260101-0000"
    END_TIME="260101-2359"
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

    file_copier "${src_dir}" "${src_dir}/file1.log" "${src_dir}/file2.log"

    # Files should be copied into SAVE_FOLDER/<stripped_path>/
    [ -d "${SAVE_FOLDER}" ]
    # Verify files were copied somewhere under SAVE_FOLDER
    local found
    found=$(find "${SAVE_FOLDER}" -name "file1.log" -type f | head -1)
    [ -n "${found}" ]
}

@test "file_copier: warns on empty files array" {
    SAVE_FOLDER="${TEST_DIR}/copy_empty"
    mkdir -p "${SAVE_FOLDER}"

    run file_copier "${TEST_DIR}/some_path"

    assert_success
    assert_output --partial "No files to copy"
}

@test "file_copier: strips /home/user/ from path" {
    SAVE_FOLDER="${TEST_DIR}/copy_strip"
    mkdir -p "${SAVE_FOLDER}"

    local src_file="${TEST_DIR}/strip_test.log"
    echo "data" > "${src_file}"

    local fake_path="/home/testuser/ros-docker/logs"
    file_copier "${fake_path}" "${src_file}"

    # After stripping /home/testuser/, save_path should be SAVE_FOLDER/ros-docker/logs
    [ -d "${SAVE_FOLDER}/ros-docker/logs" ]
}

@test "file_copier: errors with missing arguments" {
    run file_copier
    assert_failure
}

# =============================================================================
# file_sender
# =============================================================================

@test "file_sender: warns and prompts when size exceeds threshold" {
    GET_LOG_TOOL="rsync"
    SAVE_FOLDER="${TEST_DIR}/large_folder"
    mkdir -p "${SAVE_FOLDER}"
    # Create a file that makes du report > 1MB (threshold set to 1 for testing)
    dd if=/dev/zero of="${SAVE_FOLDER}/bigfile" bs=1M count=2 2>/dev/null
    TRANSFER_SIZE_WARN_MB=1

    # User answers 'n' to cancel
    run file_sender <<< "n"
    assert_failure
    assert_output --partial "MB"
}

@test "file_sender: proceeds when user confirms large transfer with Enter" {
    GET_LOG_TOOL="rsync"
    SAVE_FOLDER="${TEST_DIR}/large_yes"
    mkdir -p "${SAVE_FOLDER}"
    dd if=/dev/zero of="${SAVE_FOLDER}/bigfile" bs=1M count=2 2>/dev/null
    TRANSFER_SIZE_WARN_MB=1

    # User presses Enter (empty = yes, proceed)
    run file_sender <<< ""
    # Should proceed past the prompt (will fail at rsync since HOST=local, but that's OK)
    # The key is it does NOT show "cancelled"
    refute_output --partial "cancelled"
}

@test "file_sender: reports size in GB when folder exceeds 1GB" {
    GET_LOG_TOOL="rsync"
    SAVE_FOLDER="${TEST_DIR}/fake_huge"
    mkdir -p "${SAVE_FOLDER}"
    echo "stub" > "${SAVE_FOLDER}/marker.txt"
    TRANSFER_SIZE_WARN_MB=0  # Disable warning prompt path

    # Mock execute_cmd so the du pipeline reports 2 GB, hitting the >=1GB branch.
    execute_cmd() {
        case "$1" in
            "du -sb"*) printf '%s\n' "$((2 * 1073741824))" ;;
            "test -d"*) return 0 ;;
            *) return 0 ;;
        esac
    }

    run file_sender
    assert_output --partial "2G"
}

@test "file_sender: skips prompt when size below threshold" {
    GET_LOG_TOOL="rsync"
    SAVE_FOLDER="${TEST_DIR}/small_folder"
    mkdir -p "${SAVE_FOLDER}"
    echo "tiny" > "${SAVE_FOLDER}/small.txt"
    TRANSFER_SIZE_WARN_MB=300

    # Should not prompt — goes straight to transfer (which fails because HOST=local + rsync)
    run file_sender
    # No prompt output about "exceed" or confirmation
    refute_output --partial "exceed"
}

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

@test "file_sender: queries remote folder size with a single du call" {
    GET_LOG_TOOL="rsync"
    SAVE_FOLDER="${TEST_DIR}/du_batch"
    mkdir -p "${SAVE_FOLDER}"
    echo "x" > "${SAVE_FOLDER}/f"
    TRANSFER_SIZE_WARN_MB=300

    : > "${BATS_TEST_TMPDIR}/du_calls"
    execute_cmd() {
        case "$1" in
            "test -d "*) return 0 ;;
            *du*)
                printf '%s\n' "$1" >> "${BATS_TEST_TMPDIR}/du_calls"
                echo "10240"
                ;;
            *) return 0 ;;
        esac
    }
    export -f execute_cmd

    run file_sender
    # Don't care if rsync ultimately fails — only that du was issued exactly once
    local n
    n=$(wc -l < "${BATS_TEST_TMPDIR}/du_calls")
    assert_equal "${n}" 1
}

_setup_fake_transfer_bin() {
    FAKE_BIN="${BATS_TEST_TMPDIR}/fake_bin"
    mkdir -p "${FAKE_BIN}"
    # stub execute_cmd used by file_sender for remote probes
    execute_cmd() {
        case "$1" in
            "test -d "*) return 0 ;;
            "du -sh "*) echo "10K" ;;
            "du -sb "*) echo "10240" ;;
            *) return 0 ;;
        esac
    }
    export -f execute_cmd
}

@test "file_sender: rsync branch with VERBOSE=1 adds verbose flags" {
    _setup_fake_transfer_bin
    cat > "${FAKE_BIN}/rsync" <<'FAKE'
#!/bin/bash
echo "fake-rsync $*"
exit 0
FAKE
    chmod +x "${FAKE_BIN}/rsync"
    PATH="${FAKE_BIN}:${PATH}"

    GET_LOG_TOOL="rsync"
    SAVE_FOLDER="${TEST_DIR}/rsync_verbose"
    mkdir -p "${SAVE_FOLDER}"
    HOST="user@fakehost"
    TRANSFER_SIZE_WARN_MB=0
    VERBOSE=1

    run file_sender
    assert_success
    assert_output --partial "fake-rsync"
    assert_output --partial "--progress"
}

@test "file_sender: rsync branch succeeds via PATH-hijacked fake binary" {
    _setup_fake_transfer_bin
    cat > "${FAKE_BIN}/rsync" <<'FAKE'
#!/bin/bash
echo "fake-rsync called with: $*"
exit 0
FAKE
    chmod +x "${FAKE_BIN}/rsync"
    PATH="${FAKE_BIN}:${PATH}"

    GET_LOG_TOOL="rsync"
    SAVE_FOLDER="${TEST_DIR}/rsync_fake"
    mkdir -p "${SAVE_FOLDER}"
    HOST="user@fakehost"
    TRANSFER_SIZE_WARN_MB=0

    run file_sender
    assert_success
    assert_output --partial "fake-rsync"
}

@test "file_sender: scp branch succeeds via PATH-hijacked fake binary" {
    _setup_fake_transfer_bin
    cat > "${FAKE_BIN}/scp" <<'FAKE'
#!/bin/bash
echo "fake-scp called"
exit 0
FAKE
    chmod +x "${FAKE_BIN}/scp"
    PATH="${FAKE_BIN}:${PATH}"

    GET_LOG_TOOL="scp"
    SAVE_FOLDER="${TEST_DIR}/scp_fake"
    mkdir -p "${SAVE_FOLDER}"
    HOST="user@fakehost"
    TRANSFER_SIZE_WARN_MB=0

    run file_sender
    assert_success
    assert_output --partial "fake-scp"
}

@test "file_sender: sftp branch succeeds via PATH-hijacked fake binary" {
    _setup_fake_transfer_bin
    cat > "${FAKE_BIN}/sftp" <<'FAKE'
#!/bin/bash
cat >/dev/null
echo "fake-sftp called"
exit 0
FAKE
    chmod +x "${FAKE_BIN}/sftp"
    PATH="${FAKE_BIN}:${PATH}"

    GET_LOG_TOOL="sftp"
    SAVE_FOLDER="${TEST_DIR}/sftp_fake"
    mkdir -p "${SAVE_FOLDER}"
    HOST="user@fakehost"
    TRANSFER_SIZE_WARN_MB=0

    run file_sender
    assert_success
    assert_output --partial "fake-sftp"
}

@test "file_sender: retries then fails when rsync always fails" {
    _setup_fake_transfer_bin
    cat > "${FAKE_BIN}/rsync" <<'FAKE'
#!/bin/bash
exit 1
FAKE
    chmod +x "${FAKE_BIN}/rsync"
    PATH="${FAKE_BIN}:${PATH}"

    GET_LOG_TOOL="rsync"
    SAVE_FOLDER="${TEST_DIR}/rsync_fail"
    mkdir -p "${SAVE_FOLDER}"
    HOST="user@fakehost"
    TRANSFER_SIZE_WARN_MB=0
    TRANSFER_MAX_RETRIES=2
    TRANSFER_RETRY_DELAY=0

    run file_sender
    assert_failure
    assert_output --partial "failed after 2 attempts"
}

@test "file_sender: invokes rsync exactly TRANSFER_MAX_RETRIES times on persistent failure" {
    # The existing retry test asserts the failure message, not the loop count.
    # A log bug that silently changed `< MAX` to `<= MAX` (or vice versa) would
    # still produce the same message text, so this test counts actual binary
    # invocations to guard the boundary.
    _setup_fake_transfer_bin
    local call_log="${BATS_TEST_TMPDIR}/rsync_calls.log"
    : > "${call_log}"
    cat > "${FAKE_BIN}/rsync" <<FAKE
#!/bin/bash
echo x >> "${call_log}"
exit 1
FAKE
    chmod +x "${FAKE_BIN}/rsync"
    PATH="${FAKE_BIN}:${PATH}"

    GET_LOG_TOOL="rsync"
    SAVE_FOLDER="${TEST_DIR}/rsync_count"
    mkdir -p "${SAVE_FOLDER}"
    HOST="user@fakehost"
    TRANSFER_SIZE_WARN_MB=0
    TRANSFER_MAX_RETRIES=3
    TRANSFER_RETRY_DELAY=0

    run file_sender
    assert_failure
    local n
    n=$(wc -l < "${call_log}")
    [[ "${n}" -eq 3 ]] || {
        echo "expected rsync invoked 3 times, got ${n}" >&2
        return 1
    }
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

# --- --bwlimit integration with file_sender ---

@test "file_sender: rsync includes --bwlimit flag when BANDWIDTH_LIMIT > 0" {
    _setup_fake_transfer_bin
    cat > "${FAKE_BIN}/rsync" <<'FAKE'
#!/bin/bash
echo "fake-rsync $*"
exit 0
FAKE
    chmod +x "${FAKE_BIN}/rsync"
    PATH="${FAKE_BIN}:${PATH}"

    GET_LOG_TOOL="rsync"
    SAVE_FOLDER="${TEST_DIR}/rsync_bwlimit"
    mkdir -p "${SAVE_FOLDER}"
    HOST="user@fakehost"
    TRANSFER_SIZE_WARN_MB=0
    BANDWIDTH_LIMIT=500

    run file_sender
    assert_success
    assert_output --partial "--bwlimit=500"
}

@test "file_sender: rsync omits --bwlimit when BANDWIDTH_LIMIT is 0" {
    _setup_fake_transfer_bin
    cat > "${FAKE_BIN}/rsync" <<'FAKE'
#!/bin/bash
echo "fake-rsync $*"
exit 0
FAKE
    chmod +x "${FAKE_BIN}/rsync"
    PATH="${FAKE_BIN}:${PATH}"

    GET_LOG_TOOL="rsync"
    SAVE_FOLDER="${TEST_DIR}/rsync_no_bwlimit"
    mkdir -p "${SAVE_FOLDER}"
    HOST="user@fakehost"
    TRANSFER_SIZE_WARN_MB=0
    BANDWIDTH_LIMIT=0

    run file_sender
    assert_success
    refute_output --partial "--bwlimit"
}

@test "file_sender: scp includes -l flag with Kbit/s when BANDWIDTH_LIMIT > 0" {
    _setup_fake_transfer_bin
    cat > "${FAKE_BIN}/scp" <<'FAKE'
#!/bin/bash
echo "fake-scp $*"
exit 0
FAKE
    chmod +x "${FAKE_BIN}/scp"
    PATH="${FAKE_BIN}:${PATH}"

    GET_LOG_TOOL="scp"
    SAVE_FOLDER="${TEST_DIR}/scp_bwlimit"
    mkdir -p "${SAVE_FOLDER}"
    HOST="user@fakehost"
    TRANSFER_SIZE_WARN_MB=0
    BANDWIDTH_LIMIT=500

    run file_sender
    assert_success
    # 500 KB/s * 8 = 4000 Kbit/s
    assert_output --partial "-l 4000"
}

@test "file_sender: scp omits -l flag when BANDWIDTH_LIMIT is 0" {
    _setup_fake_transfer_bin
    cat > "${FAKE_BIN}/scp" <<'FAKE'
#!/bin/bash
echo "fake-scp $*"
exit 0
FAKE
    chmod +x "${FAKE_BIN}/scp"
    PATH="${FAKE_BIN}:${PATH}"

    GET_LOG_TOOL="scp"
    SAVE_FOLDER="${TEST_DIR}/scp_no_bwlimit"
    mkdir -p "${SAVE_FOLDER}"
    HOST="user@fakehost"
    TRANSFER_SIZE_WARN_MB=0
    BANDWIDTH_LIMIT=0

    run file_sender
    assert_success
    refute_output --partial " -l "
}

@test "file_sender: sftp includes -l flag with Kbit/s when BANDWIDTH_LIMIT > 0" {
    _setup_fake_transfer_bin
    cat > "${FAKE_BIN}/sftp" <<'FAKE'
#!/bin/bash
cat >/dev/null
echo "fake-sftp $*"
exit 0
FAKE
    chmod +x "${FAKE_BIN}/sftp"
    PATH="${FAKE_BIN}:${PATH}"

    GET_LOG_TOOL="sftp"
    SAVE_FOLDER="${TEST_DIR}/sftp_bwlimit"
    mkdir -p "${SAVE_FOLDER}"
    HOST="user@fakehost"
    TRANSFER_SIZE_WARN_MB=0
    BANDWIDTH_LIMIT=500

    run file_sender
    assert_success
    # 500 KB/s * 8 = 4000 Kbit/s
    assert_output --partial "-l 4000"
}

@test "file_sender: sftp omits -l flag when BANDWIDTH_LIMIT is 0" {
    _setup_fake_transfer_bin
    cat > "${FAKE_BIN}/sftp" <<'FAKE'
#!/bin/bash
cat >/dev/null
echo "fake-sftp $*"
exit 0
FAKE
    chmod +x "${FAKE_BIN}/sftp"
    PATH="${FAKE_BIN}:${PATH}"

    GET_LOG_TOOL="sftp"
    SAVE_FOLDER="${TEST_DIR}/sftp_no_bwlimit"
    mkdir -p "${SAVE_FOLDER}"
    HOST="user@fakehost"
    TRANSFER_SIZE_WARN_MB=0
    BANDWIDTH_LIMIT=0

    run file_sender
    assert_success
    refute_output --partial " -l "
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
    START_TIME="260115-0000"
    END_TIME="260115-2359"

    local empty_dir="${TEST_DIR}/empty_path"
    mkdir -p "${empty_dir}"

    LOG_PATHS=("${empty_dir}" "nonexistent_file*.log" "")

    run get_log
    assert_success
    assert_output --partial "No files found"
}

@test "get_log: warns with time range summary when no files found across all paths" {
    SAVE_FOLDER="${TEST_DIR}/get_log_summary"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260115-0000"
    END_TIME="260115-2359"

    local empty1="${TEST_DIR}/empty_a"
    local empty2="${TEST_DIR}/empty_b"
    mkdir -p "${empty1}" "${empty2}"

    LOG_PATHS=("${empty1}" "nope*.log" "" "${empty2}" "nada*.log" "")

    run get_log
    assert_success
    assert_output --partial "intersecting the time range 260115-0000 ~ 260115-2359"
}

@test "get_log: does NOT emit time range summary when at least one file found" {
    SAVE_FOLDER="${TEST_DIR}/get_log_partial"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260115-0000"
    END_TIME="260115-2359"

    local log_dir="${TEST_DIR}/partial_logs"
    local empty_dir="${TEST_DIR}/partial_empty"
    mkdir -p "${log_dir}" "${empty_dir}"
    touch "${log_dir}/kept.conf"

    LOG_PATHS=("${log_dir}" "kept.conf" "" "${empty_dir}" "nope*.log" "")

    run get_log
    assert_success
    refute_output --partial "intersecting the time range"
}

@test "get_log: shows resolved path after processing" {
    SAVE_FOLDER="${TEST_DIR}/get_log_resolved"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260115-0000"
    END_TIME="260115-2359"

    local log_dir="${TEST_DIR}/resolved_logs"
    mkdir -p "${log_dir}"
    touch "${log_dir}/app.conf"

    LOG_PATHS=("${log_dir}" "app.conf" "")

    run get_log
    # Should show the resolved path::prefix after the "Processing" line
    assert_output --partial "${log_dir}"
    assert_output --partial "app.conf"
    assert_output --partial "Resolved"
}

@test "get_log: copies files when found" {
    SAVE_FOLDER="${TEST_DIR}/get_log_copy"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260115-0000"
    END_TIME="260115-2359"

    local log_dir="${TEST_DIR}/app_logs"
    mkdir -p "${log_dir}"
    touch "${log_dir}/config.yaml"

    # Config file (no date token) - direct pass through
    LOG_PATHS=("${log_dir}" "config.yaml" "")

    get_log

    # Verify file was copied somewhere under SAVE_FOLDER
    local found
    found=$(find "${SAVE_FOLDER}" -name "config.yaml" -type f | head -1)
    [ -n "${found}" ]
}

@test "get_log: handles multiple log paths" {
    SAVE_FOLDER="${TEST_DIR}/get_log_multi"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260115-0000"
    END_TIME="260115-2359"

    local log_dir1="${TEST_DIR}/logs1"
    local log_dir2="${TEST_DIR}/logs2"
    mkdir -p "${log_dir1}" "${log_dir2}"
    touch "${log_dir1}/app.conf"
    touch "${log_dir2}/settings.ini"

    LOG_PATHS=("${log_dir1}" "app.conf" "" "${log_dir2}" "settings.ini" "")

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
    START_TIME="260115-0000"
    END_TIME="260115-2359"

    local log_dir="${TEST_DIR}/dated_logs"
    mkdir -p "${log_dir}"
    touch "${log_dir}/myapp_20260115120000.log"
    touch "${log_dir}/myapp_20260116120000.log"

    LOG_PATHS=("${log_dir}" "myapp_<date:%Y%m%d%H%M%S>*.log" "")

    get_log

    local found
    found=$(find "${SAVE_FOLDER}" -name "myapp_*.log" -type f | wc -l)
    # Should have copied files (at least the one in range plus expansion)
    [ "${found}" -ge 1 ]
}

@test "get_log: handles env token in path with local HOST" {
    SAVE_FOLDER="${TEST_DIR}/get_log_env"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260115-0000"
    END_TIME="260115-2359"

    local log_dir="${HOME}/test_pack_log_bats_temp"
    mkdir -p "${log_dir}"
    touch "${log_dir}/test_config.yaml"

    LOG_PATHS=("<env:HOME>/test_pack_log_bats_temp" "test_config.yaml" "")

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

@test "folder_creator: log_error when hostname/date command fails" {
    run env -u LD_PRELOAD -u BASH_ENV bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +u +o pipefail
        HOST="local"
        VERBOSE=0
        SAVE_FOLDER="'"${BATS_TEST_TMPDIR}"'/fc_test"
        # Override execute_cmd to always fail (simulates hostname/date failure)
        execute_cmd() { return 1; }
        folder_creator
    '
    assert_failure
    assert_output --partial "Failed to get hostname/date"
}

# =============================================================================
# folder_creator: token support
# =============================================================================

@test "folder_creator: <num> token resolves in SAVE_FOLDER" {
    NUM="5"
    START_TIME="260309-0000"
    SAVE_FOLDER="${TEST_DIR}/out_#<num>"
    folder_creator
    [[ "${SAVE_FOLDER}" == "${TEST_DIR}/out_#5" ]]
    [[ -d "${SAVE_FOLDER}" ]]
}

@test "folder_creator: <name> token resolves in SAVE_FOLDER" {
    NUM="1"
    START_TIME="260309-0000"
    local expected_name="${HOSTS[0]%%::*}"
    SAVE_FOLDER="${TEST_DIR}/out_<name>"
    folder_creator
    [[ "${SAVE_FOLDER}" == "${TEST_DIR}/out_${expected_name}" ]]
    [[ -d "${SAVE_FOLDER}" ]]
}

@test "folder_creator: <date:format> token resolves in SAVE_FOLDER" {
    NUM=""
    START_TIME="260309-0000"
    SAVE_FOLDER="${TEST_DIR}/out_<date:%m%d>"
    folder_creator
    [[ "${SAVE_FOLDER}" == "${TEST_DIR}/out_0309" ]]
    [[ -d "${SAVE_FOLDER}" ]]
}

@test "folder_creator: combined tokens in SAVE_FOLDER" {
    NUM="7"
    START_TIME="260309-0000"
    SAVE_FOLDER="${TEST_DIR}/corenavi_<date:%m%d>_#<num>"
    folder_creator
    [[ "${SAVE_FOLDER}" == "${TEST_DIR}/corenavi_0309_#7" ]]
    [[ -d "${SAVE_FOLDER}" ]]
}

@test "folder_creator: <num> warns and strips token when NUM is empty" {
    NUM=""
    START_TIME="260309-0000"
    SAVE_FOLDER="${TEST_DIR}/out_<num>"
    run folder_creator
    assert_output --partial "requires -n"
    # Token should be stripped, not left in the path
    [[ "${output}" != *"<num>"* ]] || [[ -d "${TEST_DIR}/out_" ]]
}

@test "folder_creator: <name> warns and strips token when NUM is empty" {
    NUM=""
    START_TIME="260309-0000"
    SAVE_FOLDER="${TEST_DIR}/out_<name>"
    run folder_creator
    assert_output --partial "requires -n"
    [[ "${output}" != *"<name>"* ]] || [[ -d "${TEST_DIR}/out_" ]]
}

# =============================================================================
# save_script_data: string_array elements (L993-996)
# =============================================================================

@test "save_script_data: string_array lines are written to script.log" {
    run env -u LD_PRELOAD -u BASH_ENV bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +u +o pipefail
        HOST="local"
        START_TIME="260115-0800"
        END_TIME="260115-1800"
        GET_LOG_TOOL="rsync"
        SAVE_FOLDER="'"${BATS_TEST_TMPDIR}"'/sd_test"
        VERBOSE=0
        LOG_PATHS=("path1" "file1" "")
        mkdir -p "${SAVE_FOLDER}"
        save_script_data
        cat "${SAVE_FOLDER}/script.log"
    '
    assert_success
    assert_output --partial "Host: local"
    assert_output --partial "Time range: 260115-0800 ~ 260115-1800"
    assert_output --partial "Using tool: rsync"
    assert_output --partial "Saving logs to folder:"
}

# =============================================================================
# file_cleaner: rm failure (L1040)
# =============================================================================

@test "file_cleaner: warns when rm -rf fails" {
    run env -u LD_PRELOAD -u BASH_ENV bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +u +o pipefail
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

@test "file_cleaner: in-process warns when rm -rf fails" {
    HOST="local"
    VERBOSE=0
    SAVE_FOLDER="/some/path"
    execute_cmd() { return 1; }
    run file_cleaner
    assert_success
    assert_output --partial "Failed to remove remote folder"
}

@test "save_script_data: in-process warns when LOG_PATHS count not multiple of 3" {
    SAVE_FOLDER="${TEST_DIR}/save_bad_count"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260115-0000"
    END_TIME="260115-2359"
    GET_LOG_TOOL="rsync"
    HOST="local"
    LOG_PATHS=("a" "b" "" "c")
    run save_script_data
    assert_output --partial "LOG_PATHS has 4 elements"
}

# =============================================================================
# get_tools_checker: no tools available (L722)
# =============================================================================

@test "get_tools_checker: in-process rsync fallback when remote lacks rsync" {
    VERBOSE=0
    HOST="fake@remote"
    pkg_install_handler() { return 0; }
    execute_cmd() { return 1; }
    run get_tools_checker
    assert_success
    assert_output --partial "rsync not available on remote host"
}

@test "get_tools_checker: in-process log_error when no tools available" {
    VERBOSE=0
    pkg_install_handler() { return 1; }
    run get_tools_checker
    assert_failure
    assert_output --partial "No file transfer tools"
}

@test "get_tools_checker: falls back past rsync when remote lacks rsync binary" {
    run env -u LD_PRELOAD -u BASH_ENV bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +u +o pipefail
        VERBOSE=0
        HOST="fake@remote"
        # rsync, scp, sftp all pass the local pkg check
        pkg_install_handler() { return 0; }
        # execute_cmd fails the remote rsync probe, so rsync branch continues.
        # After fallback, scp is chosen without re-running execute_cmd
        # (only rsync triggers the remote probe).
        execute_cmd() { return 1; }
        get_tools_checker
        echo "TOOL=${GET_LOG_TOOL}"
    '
    assert_success
    assert_output --partial "rsync not available on remote host"
    assert_output --partial "TOOL=scp"
}

@test "get_tools_checker: log_error when no tools available" {
    run env -u LD_PRELOAD -u BASH_ENV bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +u +o pipefail
        VERBOSE=0
        # Override pkg_install_handler to always fail (simulates no tools)
        pkg_install_handler() { return 1; }
        get_tools_checker
    '
    assert_failure
    assert_output --partial "No file transfer tools"
}

# =============================================================================
# get_log: LOG_PATHS element count validation
# =============================================================================

@test "file_copier: log_error when execute_cmd_from_array fails" {
    SAVE_FOLDER="${TEST_DIR}/copier_fail"
    mkdir -p "${SAVE_FOLDER}"
    local src_dir="${TEST_DIR}/copier_src"
    mkdir -p "${src_dir}"
    touch "${src_dir}/a.log"
    execute_cmd_from_array() { return 1; }
    run file_copier "${src_dir}" "${src_dir}/a.log"
    assert_failure
    assert_output --partial "Failed to copy"
}

@test "get_log_dry_run: warns when LOG_PATHS element count is not multiple of 3" {
    SAVE_FOLDER="${TEST_DIR}/dry_bad"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260115-0000"
    END_TIME="260115-2359"
    LOG_PATHS=("${TEST_DIR}" "*.txt" "" "${TEST_DIR}")
    run get_log_dry_run
    assert_output --partial "LOG_PATHS"
}

@test "get_log_dry_run: uses _needs_sudo for auto-detection, not just explicit flag" {
    START_TIME="260115-0000"
    END_TIME="260115-2359"
    HOST="local"

    # _needs_sudo returns false for /tmp/* paths, so we must simulate a path
    # outside both /tmp and HOME. Override _needs_sudo to control the result
    # and verify get_log_dry_run calls it (rather than inlining the flag check).
    local log_dir="${TEST_DIR}/outside_home"
    mkdir -p "${log_dir}"
    touch "${log_dir}/app.log"

    LOG_PATHS=("${log_dir}" "app.log" "")

    # Stub _needs_sudo to always return 0 (needs sudo) and record the call
    _needs_sudo() { echo "_NEEDS_SUDO_CALLED" >&2; return 0; }

    # Track whether file_finder receives use_sudo=true
    local orig_file_finder
    orig_file_finder="$(declare -f file_finder)"
    eval "orig_${orig_file_finder}"
    file_finder() {
        local _ff_use_sudo="${5:-false}"
        echo "SUDO_FLAG=${_ff_use_sudo}" >&2
        eval "orig_file_finder" "$@"
    }

    run get_log_dry_run
    assert_output --partial "_NEEDS_SUDO_CALLED"
    assert_output --partial "SUDO_FLAG=true"
}

@test "get_log: sudo pre-scan warns when sudo -v fails" {
    SAVE_FOLDER="${TEST_DIR}/sudo_fail"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260115-0000"
    END_TIME="260115-2359"
    HOST="local"
    local log_dir="${TEST_DIR}/sudo_fail_logs"
    mkdir -p "${log_dir}"
    touch "${log_dir}/app.conf"
    LOG_PATHS=("${log_dir}" "app.conf" "<sudo>")
    execute_cmd() {
        [[ "$1" == "sudo -v" ]] && return 1
        command bash -ls <<< "$1"
    }
    run get_log
    assert_output --partial "sudo"
}

@test "get_log: sudo pre-scan prompts when a path needs sudo" {
    SAVE_FOLDER="${TEST_DIR}/sudo_prescan"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260115-0000"
    END_TIME="260115-2359"
    HOST="local"

    local log_dir="${TEST_DIR}/sudo_logs"
    mkdir -p "${log_dir}"
    touch "${log_dir}/app.conf"

    # <sudo> flag forces _needs_sudo to return true regardless of HOME
    LOG_PATHS=("${log_dir}" "app.conf" "<sudo>")

    # Stub execute_cmd to record sudo -v call and succeed
    _SUDO_V_CALLED=0
    execute_cmd() {
        if [[ "$1" == "sudo -v" ]]; then
            _SUDO_V_CALLED=1
            return 0
        fi
        command bash -ls <<< "$1"
    }

    run get_log
    assert_output --partial "sudo"
    [[ "${_SUDO_V_CALLED}" -eq 1 ]] || {
        # _SUDO_V_CALLED lives in subshell of `run`; re-run without `run`
        _SUDO_V_CALLED=0
        get_log >/dev/null 2>&1 || true
        [[ "${_SUDO_V_CALLED}" -eq 1 ]]
    }
}

@test "get_log: calls string_handler exactly once per LOG_PATHS entry" {
    SAVE_FOLDER="${TEST_DIR}/sh_count"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260115-0000"
    END_TIME="260115-2359"
    HOST="local"

    local d1="${TEST_DIR}/sh1" d2="${TEST_DIR}/sh2" d3="${TEST_DIR}/sh3"
    mkdir -p "${d1}" "${d2}" "${d3}"
    touch "${d1}/a.conf" "${d2}/b.conf" "${d3}/c.conf"

    LOG_PATHS=(
        "${d1}" "a.conf" ""
        "${d2}" "b.conf" ""
        "${d3}" "c.conf" ""
    )

    _STRING_HANDLER_CALLS=0
    eval "_orig_string_handler() $(declare -f string_handler | tail -n +2)"
    string_handler() {
        _STRING_HANDLER_CALLS=$(( _STRING_HANDLER_CALLS + 1 ))
        _orig_string_handler "$@"
    }

    get_log >/dev/null 2>&1
    [ "${_STRING_HANDLER_CALLS}" -eq 3 ] || {
        echo "expected 3 string_handler calls, got ${_STRING_HANDLER_CALLS}" >&2
        return 1
    }
}

@test "get_log: calls _needs_sudo once per entry, not per resolved date path" {
    SAVE_FOLDER="${TEST_DIR}/ns_count"
    mkdir -p "${SAVE_FOLDER}"
    # Multi-day range so resolve_path_dates expands to several rpaths
    START_TIME="260115-0000"
    END_TIME="260118-2359"
    HOST="local"

    local base="${TEST_DIR}/dated"
    mkdir -p "${base}/2026-01-15" "${base}/2026-01-16" \
             "${base}/2026-01-17" "${base}/2026-01-18"
    touch "${base}/2026-01-15/x.log"

    LOG_PATHS=("${base}/<date:%Y-%m-%d>" "x.log" "")

    _NEEDS_SUDO_CALLS=0
    eval "_orig_needs_sudo() $(declare -f _needs_sudo | tail -n +2)"
    _needs_sudo() {
        _NEEDS_SUDO_CALLS=$(( _NEEDS_SUDO_CALLS + 1 ))
        _orig_needs_sudo "$@"
    }

    get_log >/dev/null 2>&1
    # 1 LOG_PATHS entry → expect at most 1 sudo check, not 4 (one per day)
    [ "${_NEEDS_SUDO_CALLS}" -le 1 ] || {
        echo "expected <=1 _needs_sudo call, got ${_NEEDS_SUDO_CALLS}" >&2
        return 1
    }
}

@test "get_log: runs one find per LOG_PATHS entry even when path expands to multiple dates" {
    SAVE_FOLDER="${TEST_DIR}/batch_find"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260115-0000"
    END_TIME="260118-2359"
    HOST="local"

    local base="${TEST_DIR}/multiday"
    mkdir -p "${base}/2026-01-15" "${base}/2026-01-16" \
             "${base}/2026-01-17" "${base}/2026-01-18"
    touch "${base}/2026-01-15/x.log"
    touch "${base}/2026-01-17/y.log"

    LOG_PATHS=("${base}/<date:%Y-%m-%d>" "*.log" "")

    local find_log="${BATS_TEST_TMPDIR}/find_call_log"
    : > "${find_log}"
    execute_cmd() {
        if [[ "$1" == *"find -L"* ]]; then
            echo x >> "${find_log}"
        fi
        bash -c "$1"
    }

    get_log >/dev/null 2>&1

    local n
    n=$(wc -l < "${find_log}")
    [ "${n}" -eq 1 ] || {
        echo "expected 1 find call, got ${n}" >&2
        return 1
    }

    # Verify both files copied — and into separate per-day subfolders
    local x_path y_path
    x_path=$(find "${SAVE_FOLDER}" -name x.log -type f | head -1)
    y_path=$(find "${SAVE_FOLDER}" -name y.log -type f | head -1)
    [ -n "${x_path}" ] || { echo "x.log not copied" >&2; return 1; }
    [ -n "${y_path}" ] || { echo "y.log not copied" >&2; return 1; }
    [ "$(dirname "${x_path}")" != "$(dirname "${y_path}")" ] || {
        echo "x.log and y.log ended up in same folder; per-day grouping broken" >&2
        return 1
    }
}

@test "get_log: warns when LOG_PATHS element count is not multiple of 3" {
    SAVE_FOLDER="${TEST_DIR}/bad_logpaths"
    mkdir -p "${SAVE_FOLDER}"
    START_TIME="260115-0000"
    END_TIME="260115-2359"

    # 4 elements = not multiple of 3
    LOG_PATHS=("${TEST_DIR}" "*.txt" "" "${TEST_DIR}")

    run get_log
    assert_output --partial "LOG_PATHS"
}

# =============================================================================
# archive_save_folder
# =============================================================================

@test "archive_save_folder: creates .tar.gz alongside SAVE_FOLDER" {
    SAVE_FOLDER="${TEST_DIR}/logs"
    mkdir -p "${SAVE_FOLDER}"
    echo "test" > "${SAVE_FOLDER}/file.txt"
    archive_save_folder
    [ -f "${SAVE_FOLDER}.tar.gz" ]
    tar -tzf "${SAVE_FOLDER}.tar.gz" | grep -q "logs/file.txt"
}

@test "archive_save_folder: preserves original folder" {
    SAVE_FOLDER="${TEST_DIR}/logs2"
    mkdir -p "${SAVE_FOLDER}"
    touch "${SAVE_FOLDER}/a"
    archive_save_folder
    [ -d "${SAVE_FOLDER}" ]
    [ -f "${SAVE_FOLDER}/a" ]
}

@test "archive_save_folder: archive uses relative paths (no absolute)" {
    SAVE_FOLDER="${TEST_DIR}/logs3"
    mkdir -p "${SAVE_FOLDER}"
    touch "${SAVE_FOLDER}/a.log"
    archive_save_folder
    ! tar -tzf "${SAVE_FOLDER}.tar.gz" | grep -q "^/"
}

@test "archive_save_folder: reports apparent size, not filesystem block usage" {
    SAVE_FOLDER="${TEST_DIR}/sz_logs"
    mkdir -p "${SAVE_FOLDER}"
    # Tiny content → tar.gz will be ~hundreds of bytes (well under one 4K block)
    echo "tiny" > "${SAVE_FOLDER}/f.txt"

    VERBOSE=1
    local out
    out=$(archive_save_folder 2>&1)

    local apparent block
    apparent=$(du -h --apparent-size "${SAVE_FOLDER}.tar.gz" | cut -f1)
    block=$(du -h "${SAVE_FOLDER}.tar.gz" | cut -f1)

    # Sanity: this test is only meaningful when the two differ
    [ "${apparent}" != "${block}" ] || skip "fs block size matches apparent (no rounding to assert)"

    [[ "${out}" == *"${apparent}"* ]] || {
        echo "expected output to contain apparent size '${apparent}'" >&2
        echo "got: ${out}" >&2
        return 1
    }
    [[ "${out}" != *"(${block})"* ]] || {
        echo "output still contains block-rounded size '${block}'" >&2
        echo "got: ${out}" >&2
        return 1
    }
}

@test "archive_save_folder: returns 1 when SAVE_FOLDER missing" {
    SAVE_FOLDER="${TEST_DIR}/nonexistent"
    run archive_save_folder
    assert_failure
    assert_output --partial "Cannot archive"
}

@test "archive_save_folder: interactive [R]etry loop invokes archive again before accepting [K]" {
    # Gap filled: existing tests check the final exit state, but not that the
    # retry branch actually re-runs archive_save_folder when the user enters
    # an empty line. A silent regression dropping the `continue` would pass
    # the current tests because the second response ('k') eventually succeeds.
    SAVE_FOLDER="${TEST_DIR}/retry_loop"
    mkdir -p "${SAVE_FOLDER}"
    local call_log="${BATS_TEST_TMPDIR}/archive_calls.log"
    : > "${call_log}"
    archive_save_folder() {
        echo x >> "${call_log}"
        return 1
    }
    export -f archive_save_folder 2>/dev/null || true

    # First empty line → retry, second 'k' → break and succeed.
    run main -l -s 260115-0000 -e 260115-2359 \
        -o "${BATS_TEST_TMPDIR}/ar_loop" < <(printf '\nk\n')

    # Regardless of exit code, the retry loop must have hit the failing
    # archive function at least twice (initial + retry).
    local n
    n=$(wc -l < "${call_log}")
    [[ "${n}" -ge 2 ]] || {
        echo "expected archive_save_folder to be invoked >=2 times, got ${n}" >&2
        echo "---output---"
        echo "${output}"
        return 1
    }
}

@test "archive_save_folder: returns 1 and removes partial archive when tar fails" {
    SAVE_FOLDER="${TEST_DIR}/logs4"
    mkdir -p "${SAVE_FOLDER}"
    local fake_bin="${TEST_DIR}/fake_bin"
    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/tar" <<'EOF'
#!/bin/bash
prev=""
for arg in "$@"; do
  if [[ "${prev}" == "-czf" || "${prev}" == "-f" || "${prev}" == "--file" ]]; then
    echo "partial garbage" > "${arg}"
    break
  fi
  prev="${arg}"
done
exit 2
EOF
    chmod +x "${fake_bin}/tar"
    PATH="${fake_bin}:${PATH}" run archive_save_folder
    assert_failure
    assert_output --partial "Failed to create archive"
    [ ! -e "${SAVE_FOLDER}.tar.gz" ]
}
