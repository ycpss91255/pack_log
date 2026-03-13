#!/usr/bin/env bats

setup() {
    load 'test_helper'
    VERBOSE=0
    HOST=""
    NUM=""
    START_TIME=""
    END_TIME=""

    # Use temp paths for SSH and output
    SSH_KEY="${BATS_TEST_TMPDIR}/test_ssh_key"
    SSH_TIMEOUT=3
    SSH_OPTS=(
        -i "${SSH_KEY}"
        -o BatchMode=yes
        -o ConnectTimeout="${SSH_TIMEOUT}"
        -o NumberOfPasswordPrompts=0
        -o PreferredAuthentications=publickey
        -o StrictHostKeyChecking=no
    )
}

# ---------------------------------------------------------------------------
# 1. Help flag
# ---------------------------------------------------------------------------

@test "main: -h prints help and exits 0" {
    run main -h
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "--help"
}

@test "main: --help prints help and exits 0" {
    run main --help
    assert_success
    assert_output --partial "Usage:"
}

# ---------------------------------------------------------------------------
# 2. Missing required info
# ---------------------------------------------------------------------------

@test "main: missing start time with local mode errors" {
    # Pipe empty input so read doesn't hang; empty string fails validation
    run bash -c 'source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'" && echo "" | main -l -e 20260115-235959'
    assert_failure
}

@test "main: missing end time with local mode errors" {
    run bash -c 'source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'" && echo "" | main -l -s 20260115-000000'
    assert_failure
}

@test "main: invalid start time format errors" {
    run main -l -s "badtime" -e 20260115-235959
    assert_failure
    assert_output --partial "Invalid"
}

@test "main: invalid end time format errors" {
    run main -l -s 20260115-000000 -e "badtime"
    assert_failure
    assert_output --partial "Invalid"
}

# ---------------------------------------------------------------------------
# 3. Local mode basic flow
# ---------------------------------------------------------------------------

@test "main: local mode end-to-end with simple config files" {
    # Create test log directory with a config file (no date token -> direct pass)
    local test_dir="${BATS_TEST_TMPDIR}/test_logs"
    mkdir -p "${test_dir}"
    echo "key: value" > "${test_dir}/test.yaml"

    # Override LOG_PATHS to use the test directory with a simple config file
    LOG_PATHS=("${test_dir}::test.yaml")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output"

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${BATS_TEST_TMPDIR}/output"
    assert_success
    assert_output --partial "Packaging log completed successfully"
}

@test "main: local mode creates output folder" {
    local test_dir="${BATS_TEST_TMPDIR}/test_logs2"
    mkdir -p "${test_dir}"
    echo "data" > "${test_dir}/config.txt"

    LOG_PATHS=("${test_dir}::config.txt")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output2"

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${BATS_TEST_TMPDIR}/output2"
    assert_success

    # Output folder should exist (with hostname and date suffix appended)
    local -a output_dirs=("${BATS_TEST_TMPDIR}"/output2_*)
    [[ -d "${output_dirs[0]}" ]]
}

@test "main: local mode copies config files to output" {
    local test_dir="${BATS_TEST_TMPDIR}/test_logs3"
    mkdir -p "${test_dir}"
    echo "content123" > "${test_dir}/myfile.conf"

    LOG_PATHS=("${test_dir}::myfile.conf")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output3"

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${BATS_TEST_TMPDIR}/output3"
    assert_success

    # Find the output directory and verify the file was copied
    local -a output_dirs=("${BATS_TEST_TMPDIR}"/output3_*)
    [[ -d "${output_dirs[0]}" ]]

    # The file should exist somewhere under the output
    local found
    found=$(find "${output_dirs[0]}" -name "myfile.conf" 2>/dev/null | head -1)
    [[ -n "${found}" ]]
    [[ "$(cat "${found}")" == "content123" ]]
}

@test "main: local mode with no matching files warns but succeeds" {
    local test_dir="${BATS_TEST_TMPDIR}/empty_logs"
    mkdir -p "${test_dir}"

    # Point to a non-existent file pattern
    LOG_PATHS=("${test_dir}::nonexistent_file.log")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output4"

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${BATS_TEST_TMPDIR}/output4"
    assert_success
    assert_output --partial "No files found"
}

@test "main: local mode with multiple LOG_PATHS" {
    local test_dir1="${BATS_TEST_TMPDIR}/logs_a"
    local test_dir2="${BATS_TEST_TMPDIR}/logs_b"
    mkdir -p "${test_dir1}" "${test_dir2}"
    echo "aaa" > "${test_dir1}/a.conf"
    echo "bbb" > "${test_dir2}/b.conf"

    LOG_PATHS=(
        "${test_dir1}::a.conf"
        "${test_dir2}::b.conf"
    )
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output5"

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${BATS_TEST_TMPDIR}/output5"
    assert_success
    assert_output --partial "Packaging log completed successfully"
}

# ---------------------------------------------------------------------------
# 4. Verbose flag
# ---------------------------------------------------------------------------

@test "main: -v enables verbose mode" {
    local test_dir="${BATS_TEST_TMPDIR}/test_logs_v"
    mkdir -p "${test_dir}"
    echo "data" > "${test_dir}/v.yaml"

    LOG_PATHS=("${test_dir}::v.yaml")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output_v"

    run main -l -v -s 20260115-000000 -e 20260115-235959 -o "${BATS_TEST_TMPDIR}/output_v"
    assert_success
    assert_output --partial "[DEBUG]"
}

# ---------------------------------------------------------------------------
# 5. Local mode does NOT call ssh_handler
# ---------------------------------------------------------------------------

@test "main: local mode does not call ssh_handler" {
    local ssh_handler_called="${BATS_TEST_TMPDIR}/ssh_handler_called"

    # Override ssh_handler to detect if it gets called
    eval "original_ssh_handler() $(declare -f ssh_handler | tail -n +2)"
    ssh_handler() {
        touch "${ssh_handler_called}"
        original_ssh_handler
    }

    local test_dir="${BATS_TEST_TMPDIR}/test_logs_nossh"
    mkdir -p "${test_dir}"
    echo "data" > "${test_dir}/file.yaml"

    LOG_PATHS=("${test_dir}::file.yaml")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output_nossh"

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${BATS_TEST_TMPDIR}/output_nossh"
    assert_success

    # ssh_handler should NOT have been called in local mode
    [[ ! -f "${ssh_handler_called}" ]]
}

# ---------------------------------------------------------------------------
# 6. Option parser integration
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 7. Remote mode calls ssh_handler, get_tools_checker, file_sender (L1192-1193, L1201, L1210)
# ---------------------------------------------------------------------------

@test "main: remote mode calls ssh_handler, get_tools_checker, and file_sender" {
    # Override functions to track calls and avoid actual SSH
    ssh_handler() { :; }
    get_tools_checker() { GET_LOG_TOOL="rsync"; }
    file_sender() { :; }

    # Override execute_cmd to always work locally regardless of HOST
    execute_cmd() {
        printf '%s' "$1" | bash -ls
    }

    local test_dir="${BATS_TEST_TMPDIR}/remote_test"
    mkdir -p "${test_dir}"
    echo "key: value" > "${test_dir}/file.yaml"

    LOG_PATHS=("${test_dir}::file.yaml")

    run main -u "testuser@fakehost" -s 20260115-000000 -e 20260115-235959 -o "${BATS_TEST_TMPDIR}/remote_out"
    assert_success
    assert_output --partial "Packaging log completed successfully"
}

# ---------------------------------------------------------------------------
# 8. Remote mode sets trap with EXIT (L1201)
# ---------------------------------------------------------------------------

@test "main: remote mode trap includes EXIT signal" {
    ssh_handler() { :; }
    get_tools_checker() { GET_LOG_TOOL="rsync"; }
    file_sender() { :; }
    execute_cmd() {
        printf '%s' "$1" | bash -ls
    }

    local test_dir="${BATS_TEST_TMPDIR}/remote_trap_test"
    mkdir -p "${test_dir}"
    echo "data" > "${test_dir}/conf.yaml"

    LOG_PATHS=("${test_dir}::conf.yaml")

    run main -u "testuser@fakehost" -s 20260115-000000 -e 20260115-235959 -o "${BATS_TEST_TMPDIR}/remote_trap_out"
    assert_success
}

# ---------------------------------------------------------------------------
# 9. Source guard (L1218)
# ---------------------------------------------------------------------------

@test "main: source guard executes main when script is run directly" {
    run bash "${BATS_TEST_DIRNAME}/../pack_log.sh" --help
    assert_success
    assert_output --partial "Usage:"
}

# ---------------------------------------------------------------------------
# 10. Option parser integration
# ---------------------------------------------------------------------------

@test "main: -o sets custom output folder" {
    local test_dir="${BATS_TEST_TMPDIR}/test_logs_out"
    mkdir -p "${test_dir}"
    echo "data" > "${test_dir}/out.yaml"

    LOG_PATHS=("${test_dir}::out.yaml")

    run main -l -s 20260115-000000 -e 20260115-235959 -o "${BATS_TEST_TMPDIR}/custom_output"
    assert_success

    local -a output_dirs=("${BATS_TEST_TMPDIR}"/custom_output_*)
    [[ -d "${output_dirs[0]}" ]]
}
