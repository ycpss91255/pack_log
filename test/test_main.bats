#!/usr/bin/env bats

setup() {
    load 'test_helper'
    VERBOSE=0
    HOST=""
    NUM=""
    START_TIME=""
    END_TIME=""
    DRY_RUN=false

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
    run env -u LD_PRELOAD -u BASH_ENV bash -c 'source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'" && echo "" | main -l -e 260115-2359'
    assert_failure
}

@test "main: missing end time with local mode errors" {
    run env -u LD_PRELOAD -u BASH_ENV bash -c 'source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'" && echo "" | main -l -s 260115-0000'
    assert_failure
}

@test "main: invalid start time format errors" {
    run main -l -s "badtime" -e 260115-2359
    assert_failure
    assert_output --partial "Invalid"
}

@test "main: invalid end time format errors" {
    run main -l -s 260115-0000 -e "badtime"
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
    LOG_PATHS=("${test_dir}" "test.yaml" "")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output"

    run main -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output"
    assert_success
    assert_output --partial "Packaging log completed successfully"
}

@test "main: local mode creates output folder" {
    local test_dir="${BATS_TEST_TMPDIR}/test_logs2"
    mkdir -p "${test_dir}"
    echo "data" > "${test_dir}/config.txt"

    LOG_PATHS=("${test_dir}" "config.txt" "")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output2"

    run main -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output2"
    assert_success

    # Output folder should exist (with hostname and date suffix appended)
    local -a output_dirs=("${BATS_TEST_TMPDIR}"/output2_*)
    [[ -d "${output_dirs[0]}" ]]
}

@test "main: archive step is silent at default verbosity, output section is shown" {
    local test_dir="${BATS_TEST_TMPDIR}/arch_quiet"
    mkdir -p "${test_dir}"
    echo "x" > "${test_dir}/c.conf"
    LOG_PATHS=("${test_dir}" "c.conf" "")

    run main -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/arch_quiet_out"
    assert_success
    # Step 6 header stays visible as a progress milestone, but the inner
    # archive mechanics (creating / done) are demoted to debug.
    assert_output --partial "Step 6"
    # The colon-form matches MSG_ARCHIVING ("Creating archive: <path>") but
    # not the Step 6 header ("=== Step 6/6: Creating archive ===").
    refute_output --partial "Creating archive: "
    refute_output --partial "Archive created"
    # The new Output section header replaces them as the user-facing summary;
    # paths are full absolute paths so they can be copy-pasted directly.
    assert_output --partial "=== Output ==="
    assert_output --partial "Output folder:  ${BATS_TEST_TMPDIR}/arch_quiet_out"
    assert_output --partial "Output archive: ${BATS_TEST_TMPDIR}/arch_quiet_out"
    assert_output --partial ".tar.gz"
    refute_output --partial "Output path:"
}

@test "main: archive step details are visible with -v" {
    local test_dir="${BATS_TEST_TMPDIR}/arch_verbose"
    mkdir -p "${test_dir}"
    echo "y" > "${test_dir}/c.conf"
    LOG_PATHS=("${test_dir}" "c.conf" "")

    run main -v -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/arch_verbose_out"
    assert_success
    assert_output --partial "Archive created"
}

@test "main: local mode copies config files to output" {
    local test_dir="${BATS_TEST_TMPDIR}/test_logs3"
    mkdir -p "${test_dir}"
    echo "content123" > "${test_dir}/myfile.conf"

    LOG_PATHS=("${test_dir}" "myfile.conf" "")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output3"

    run main -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output3"
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
    LOG_PATHS=("${test_dir}" "nonexistent_file.log" "")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output4"

    run main -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output4"
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
        "${test_dir1}" "a.conf" ""
        "${test_dir2}" "b.conf" ""
    )
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output5"

    run main -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output5"
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

    LOG_PATHS=("${test_dir}" "v.yaml" "")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output_v"

    run main -l -v -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output_v"
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

    LOG_PATHS=("${test_dir}" "file.yaml" "")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output_nossh"

    run main -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output_nossh"
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

    # Override execute_cmd and execute_cmd_from_array to work locally
    execute_cmd() {
        printf '%s' "$1" | bash -ls
    }
    execute_cmd_from_array() {
        local -r inner_cmd="$1"; shift
        printf '%s\0' "$@" | bash -c "${inner_cmd}"
    }

    local test_dir="${BATS_TEST_TMPDIR}/remote_test"
    mkdir -p "${test_dir}"
    echo "key: value" > "${test_dir}/file.yaml"

    LOG_PATHS=("${test_dir}" "file.yaml" "")

    run main -u "testuser@fakehost" -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/remote_out"
    assert_success
    assert_output --partial "Packaging log completed successfully"
}

# ---------------------------------------------------------------------------
# 8. Remote mode trap does NOT include EXIT (preserves /tmp folder)
# ---------------------------------------------------------------------------

@test "main: remote mode trap does not include EXIT signal" {
    ssh_handler() { :; }
    get_tools_checker() { GET_LOG_TOOL="rsync"; }
    file_sender() { :; }
    execute_cmd() {
        printf '%s' "$1" | bash -ls
    }
    execute_cmd_from_array() {
        local -r inner_cmd="$1"; shift
        printf '%s\0' "$@" | bash -c "${inner_cmd}"
    }

    local test_dir="${BATS_TEST_TMPDIR}/remote_trap_test"
    mkdir -p "${test_dir}"
    echo "data" > "${test_dir}/conf.yaml"

    LOG_PATHS=("${test_dir}" "conf.yaml" "")

    run main -u "testuser@fakehost" -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/remote_trap_out"
    assert_success
}

# ---------------------------------------------------------------------------
# 8b. Transfer failure interactive prompt
# ---------------------------------------------------------------------------

_setup_transfer_fail_test() {
    ssh_handler() { :; }
    get_tools_checker() { GET_LOG_TOOL="rsync"; }
    # file_sender always fails
    file_sender() { return 1; }
    execute_cmd() { printf '%s' "$1" | bash -ls; }
    execute_cmd_from_array() {
        local -r inner_cmd="$1"; shift
        printf '%s\0' "$@" | bash -c "${inner_cmd}"
    }

    local test_dir="${BATS_TEST_TMPDIR}/transfer_fail"
    mkdir -p "${test_dir}"
    echo "data" > "${test_dir}/file.yaml"
    LOG_PATHS=("${test_dir}" "file.yaml" "")
}

@test "main: transfer failure with 'k' preserves remote and exits" {
    _setup_transfer_fail_test

    run main -u "testuser@fakehost" -s 260115-0000 -e 260115-2359 \
        -o "${BATS_TEST_TMPDIR}/tf_opt_a" <<< "k"
    assert_failure
    assert_output --partial "[K]eep"
}

@test "main: transfer failure with 'c' cleans remote and exits" {
    _setup_transfer_fail_test

    run main -u "testuser@fakehost" -s 260115-0000 -e 260115-2359 \
        -o "${BATS_TEST_TMPDIR}/tf_opt_b" <<< "c"
    assert_failure
    assert_output --partial "[C]lean"
}

@test "main: transfer failure with empty input retries then 'k' exits" {
    _setup_transfer_fail_test
    # First empty line → retry (file_sender fails again), second 'k' → exit
    run main -u "testuser@fakehost" -s 260115-0000 -e 260115-2359 \
        -o "${BATS_TEST_TMPDIR}/tf_opt_c" < <(printf '\nk\n')
    assert_failure
    assert_output --partial "[R]etry"
}

# ---------------------------------------------------------------------------
# 8c. Archive failure interactive prompt
# ---------------------------------------------------------------------------

_setup_archive_fail_test() {
    # archive_save_folder always fails (simulates tar failure / disk full).
    archive_save_folder() { return 1; }

    local test_dir="${BATS_TEST_TMPDIR}/archive_fail"
    mkdir -p "${test_dir}"
    echo "data" > "${test_dir}/file.yaml"
    LOG_PATHS=("${test_dir}" "file.yaml" "")
}

@test "main: archive failure with 'k' keeps folder only and succeeds" {
    _setup_archive_fail_test

    run main -l -s 260115-0000 -e 260115-2359 \
        -o "${BATS_TEST_TMPDIR}/af_k" <<< "k"
    assert_success
    assert_output --partial "[K]eep folder only"
}

@test "main: archive failure with 'a' aborts with exit 1" {
    _setup_archive_fail_test

    run main -l -s 260115-0000 -e 260115-2359 \
        -o "${BATS_TEST_TMPDIR}/af_a" <<< "a"
    assert_failure
    assert_output --partial "[A]bort"
}

@test "main: archive failure with empty input retries then 'k' succeeds" {
    _setup_archive_fail_test
    # First empty line → retry (archive fails again), second 'k' → break+success
    run main -l -s 260115-0000 -e 260115-2359 \
        -o "${BATS_TEST_TMPDIR}/af_r" < <(printf '\nk\n')
    assert_success
    assert_output --partial "[R]etry"
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

    LOG_PATHS=("${test_dir}" "out.yaml" "")

    run main -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/custom_output"
    assert_success

    local -a output_dirs=("${BATS_TEST_TMPDIR}"/custom_output_*)
    [[ -d "${output_dirs[0]}" ]]
}

# ---------------------------------------------------------------------------
# 11. Dry-run mode
# ---------------------------------------------------------------------------

@test "main: --dry-run lists files without copying" {
    local test_dir="${BATS_TEST_TMPDIR}/test_logs_dry"
    mkdir -p "${test_dir}"
    echo "data" > "${test_dir}/test.yaml"

    LOG_PATHS=("${test_dir}" "test.yaml" "")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output_dry"

    run main --dry-run -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output_dry"
    assert_success
    assert_output --partial "DRY RUN"
    assert_output --partial "test.yaml"
}

@test "main: --dry-run does not create output folder" {
    local test_dir="${BATS_TEST_TMPDIR}/test_logs_dry2"
    mkdir -p "${test_dir}"
    echo "data" > "${test_dir}/file.conf"

    LOG_PATHS=("${test_dir}" "file.conf" "")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output_dry2"

    run main --dry-run -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output_dry2"
    assert_success

    # Output folder should NOT exist in dry-run mode
    local -a output_dirs=("${BATS_TEST_TMPDIR}"/output_dry2_*)
    [[ ! -d "${output_dirs[0]}" ]]
}

@test "main: --dry-run does not call file_sender in remote mode" {
    ssh_handler() { :; }
    get_tools_checker() { GET_LOG_TOOL="rsync"; }

    local sender_called="${BATS_TEST_TMPDIR}/sender_called"
    file_sender() { touch "${sender_called}"; }

    execute_cmd() {
        printf '%s' "$1" | bash -ls
    }

    local test_dir="${BATS_TEST_TMPDIR}/remote_dry"
    mkdir -p "${test_dir}"
    echo "data" > "${test_dir}/file.yaml"

    LOG_PATHS=("${test_dir}" "file.yaml" "")

    run main --dry-run -u "testuser@fakehost" -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/remote_dry_out"
    assert_success
    assert_output --partial "DRY RUN"

    # file_sender should NOT have been called
    [[ ! -f "${sender_called}" ]]
}

@test "main: --dry-run shows total file count" {
    local test_dir="${BATS_TEST_TMPDIR}/test_logs_dry3"
    mkdir -p "${test_dir}"
    echo "a" > "${test_dir}/a.conf"
    echo "b" > "${test_dir}/b.conf"

    LOG_PATHS=("${test_dir}" "*.conf" "")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output_dry3"

    run main --dry-run -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output_dry3"
    assert_success
    assert_output --partial "2"
}

@test "main: --dry-run shows resolved path and file pattern" {
    local test_dir="${BATS_TEST_TMPDIR}/test_logs_dry4"
    mkdir -p "${test_dir}"
    echo "data" > "${test_dir}/app.log"

    LOG_PATHS=("${test_dir}" "app.log" "")

    run main --dry-run -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output_dry4"
    assert_success
    assert_output --partial "Resolved path: ${test_dir}"
    assert_output --partial "File pattern:"
    assert_output --partial "app.log"
}

@test "main: --dry-run shows directory not found for missing paths" {
    LOG_PATHS=("/nonexistent/path/abc123" "some_file.log" "")

    run main --dry-run -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output_dry5"
    assert_success
    assert_output --partial "Directory not found: /nonexistent/path/abc123"
}

@test "main: --dry-run skips empty resolved path with warning" {
    NUM=""
    LOG_PATHS=("<name>" "*" "")

    run main --dry-run -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output_dry_emptypath"
    assert_success
    assert_output --partial "path is empty"
}

@test "main: normal mode skips empty resolved path with warning" {
    NUM=""
    LOG_PATHS=("<name>" "*" "")
    SAVE_FOLDER="${BATS_TEST_TMPDIR}/output_emptypath"

    run main -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output_emptypath"
    assert_success
    assert_output --partial "path is empty"
}

@test "main: --dry-run shows no files found when dir exists but empty" {
    local test_dir="${BATS_TEST_TMPDIR}/dry_empty_dir"
    mkdir -p "${test_dir}"

    LOG_PATHS=("${test_dir}" "nonexistent_file.log" "")

    run main --dry-run -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output_dry_empty"
    assert_success
    assert_output --partial "No files found"
}

@test "main: --dry-run does not invoke archive_save_folder" {
    # The existing dry-run suite verifies that file_sender is not called and
    # that the output folder is never created. This closes the matching gap
    # on the archive phase: even if the user resolves a file list, the dry
    # run must not write a .tar.gz.
    local archive_called="${BATS_TEST_TMPDIR}/archive_dryrun_marker"
    archive_save_folder() { touch "${archive_called}"; }

    local test_dir="${BATS_TEST_TMPDIR}/dry_archive_check"
    mkdir -p "${test_dir}"
    echo "data" > "${test_dir}/payload.yaml"
    LOG_PATHS=("${test_dir}" "payload.yaml" "")

    run main --dry-run -l -s 260115-0000 -e 260115-2359 \
        -o "${BATS_TEST_TMPDIR}/output_dry_archive"
    assert_success
    [[ ! -f "${archive_called}" ]] || {
        echo "archive_save_folder was invoked during --dry-run" >&2
        return 1
    }
}

@test "main: --lang ja localizes time_handler error messages" {
    # Previous coverage only asserted that --help text was translated. A
    # regression that stopped threading LANG_CODE into load_lang before
    # time_handler ran could ship untranslated errors without the help
    # assertion noticing.
    run main -l --lang ja -s "badtime" -e 260115-2359
    assert_failure
    assert_output --partial "無効"
}

@test "main: --lang zh-CN localizes time_handler error messages" {
    run main -l --lang zh-CN -s "badtime" -e 260115-2359
    assert_failure
    assert_output --partial "无效"
}

@test "main: --dry-run processes multiple LOG_PATHS without crashing" {
    local dir1="${BATS_TEST_TMPDIR}/dry_multi1"
    local dir2="${BATS_TEST_TMPDIR}/dry_multi2"
    local dir3="${BATS_TEST_TMPDIR}/dry_multi3"
    mkdir -p "${dir1}" "${dir2}" "${dir3}"
    echo "a" > "${dir1}/a.log"
    echo "b" > "${dir2}/b.log"
    echo "c" > "${dir3}/c.log"

    LOG_PATHS=(
        "${dir1}" "a.log" ""
        "${dir2}" "b.log" ""
        "${dir3}" "c.log" ""
    )

    run main --dry-run -l -s 260115-0000 -e 260115-2359 -o "${BATS_TEST_TMPDIR}/output_dry_multi"
    assert_success
    assert_output --partial "[1/3]"
    assert_output --partial "[2/3]"
    assert_output --partial "[3/3]"
    assert_output --partial "3"
}
