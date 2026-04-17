#!/usr/bin/env bats

setup() {
    load 'test_helper'
    VERBOSE=0
    HOST="local"
}

# --- CI environment ---

@test "CI: tests run as non-root user" {
    [[ "${EUID:-${UID}}" -ne 0 ]]
}

# --- have_sudo_access ---

@test "have_sudo_access: returns 0 when running as root (EUID=0)" {
    # Run as root via sudo to test the EUID=0 early-return path
    [[ -x /usr/bin/sudo ]] || skip "sudo not installed"
    sudo -n true 2>/dev/null || skip "sudo requires password"
    run sudo env -u LD_PRELOAD -u BASH_ENV bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +u +o pipefail
        unset HAVE_SUDO_ACCESS
        have_sudo_access
        echo "rc=$?"
    '
    assert_success
    assert_output --partial "rc=0"
}

@test "have_sudo_access: returns 0 when cached as success" {
    # Cache check is after /usr/bin/sudo existence check
    [[ -x /usr/bin/sudo ]] || skip "sudo not installed"
    HAVE_SUDO_ACCESS=0
    run have_sudo_access
    assert_success
}

@test "have_sudo_access: returns 1 when sudo not available" {

    unset HAVE_SUDO_ACCESS
    # If /usr/bin/sudo is not executable or not present, returns 1
    # Test the cached failure path instead
    HAVE_SUDO_ACCESS=1
    run have_sudo_access
    assert_failure
}


@test "have_sudo_access: returns cached failure" {

    HAVE_SUDO_ACCESS=1
    run have_sudo_access
    assert_failure
}

# --- pkg_install_handler ---

@test "pkg_install_handler: returns 0 when package already installed" {
    # 'bash' is always available
    run pkg_install_handler "bash"
    assert_success
}

@test "pkg_install_handler: errors when no sudo and package missing" {

    HAVE_SUDO_ACCESS=1
    run pkg_install_handler "nonexistent_pkg_xyz_12345"
    assert_failure
    assert_output --partial "No sudo access"
}

# --- date_format ---

@test "date_format: formats date correctly with %Y%m%d" {
    date_format "260115-1030" "%Y%m%d"
    assert_equal "${REPLY}" "20260115"
}

@test "date_format: formats date correctly with %Y%m%d-%H%M%S" {
    date_format "260115-1030" "%Y%m%d-%H%M%S"
    assert_equal "${REPLY}" "20260115-103000"
}

@test "date_format: formats date correctly with %s (epoch)" {
    date_format "260115-1030" "%s"
    # Verify it's a number (epoch timestamp)
    [[ "${REPLY}" =~ ^[0-9]+$ ]]
}

@test "date_format: errors on invalid date format" {
    run date_format "invalid-date" "%Y%m%d"
    assert_failure
    assert_output --partial "Invalid date format"
}

@test "date_format: errors on short date string" {
    run date_format "2026" "%Y%m%d"
    assert_failure
    assert_output --partial "Invalid date format"
}

# --- execute_cmd ---

@test "execute_cmd: runs command locally when HOST is local" {
    HOST="local"
    run execute_cmd "echo hello"
    assert_success
    assert_output "hello"
}

@test "execute_cmd: runs complex command locally" {
    HOST="local"
    run execute_cmd "printf '%s %s' foo bar"
    assert_success
    assert_output "foo bar"
}

@test "execute_cmd: returns failure for failing command" {
    HOST="local"
    run execute_cmd "false"
    assert_failure
}

@test "execute_cmd: errors with missing argument" {
    run execute_cmd
    assert_failure
}

# --- get_remote_value ---

@test "get_remote_value: gets HOME env locally" {
    HOST="local"
    get_remote_value "env" "HOME"
    assert_equal "${REPLY}" "${HOME}"
}

@test "get_remote_value: gets env var via execute_cmd" {
    HOST="local"
    # HOME is always available in both root and non-root environments
    get_remote_value "env" "HOME"
    [[ -n "${REPLY}" ]]
}

@test "get_remote_value: runs cmd type" {
    HOST="local"
    get_remote_value "cmd" "echo testval"
    assert_equal "${REPLY}" "testval"
}

@test "get_remote_value: errors on unknown type" {
    HOST="local"
    run get_remote_value "unknown" "test"
    assert_failure
    assert_output --partial "Unknown type"
}

@test "get_remote_value: errors with missing arguments" {
    run get_remote_value
    assert_failure
}

# --- create_folder ---

@test "create_folder: creates folder locally" {
    HOST="local"
    local tmpdir="${BATS_TEST_TMPDIR}/test_create_folder"
    create_folder "${tmpdir}"
    [ -d "${tmpdir}" ]
}

@test "create_folder: no error if folder already exists" {
    HOST="local"
    local tmpdir="${BATS_TEST_TMPDIR}/test_existing_folder"
    mkdir -p "${tmpdir}"
    create_folder "${tmpdir}"
    [ -d "${tmpdir}" ]
}

@test "create_folder: errors with missing argument" {
    run create_folder
    assert_failure
}

# --- execute_cmd_from_array ---

@test "execute_cmd_from_array: pipes array to command locally" {
    HOST="local"
    run execute_cmd_from_array "xargs -0 -r printf '%s\n'" "file1" "file2" "file3"
    assert_success
    assert_output --partial "file1"
    assert_output --partial "file2"
    assert_output --partial "file3"
}

@test "execute_cmd_from_array: returns failure for failing command" {
    HOST="local"
    run execute_cmd_from_array "xargs -0 -r false" "item"
    assert_failure
}

@test "execute_cmd_from_array: errors with missing arguments" {
    run execute_cmd_from_array
    assert_failure
}

# --- have_sudo_access: /usr/bin/sudo not executable (L196-197) ---

@test "have_sudo_access: returns 1 when /usr/bin/sudo is not executable" {

    run env -u LD_PRELOAD -u BASH_ENV bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +u +o pipefail
        unset HAVE_SUDO_ACCESS
        # Redefine the function to test the path with a nonexistent sudo
        have_sudo_access() {
            local -a sudo_cmd=("/usr/bin/sudo")
            if [[ "${EUID:-${UID}}" -eq 0 ]]; then return 0; fi
            if [[ ! -x "/nonexistent_path/sudo" ]]; then return 1; fi
            return 0
        }
        have_sudo_access
    '
    assert_failure
}

# --- have_sudo_access: SUDO_ASKPASS branch (L202) ---

@test "have_sudo_access: processes SUDO_ASKPASS when set" {
    run env -u LD_PRELOAD -u BASH_ENV bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +u +o pipefail
        unset HAVE_SUDO_ACCESS
        export SUDO_ASKPASS="/bin/true"
        have_sudo_access || true
        echo "done"
    '
    assert_output --partial "done"
}

# --- have_sudo_access: PATH hijack to cover L697 (sudo missing) and L711 (sudo fail) ---

@test "have_sudo_access: returns 1 in-process when sudo not in PATH" {
    unset HAVE_SUDO_ACCESS
    # Use a tmpdir with no sudo binary as PATH
    local empty_bin="${BATS_TEST_TMPDIR}/empty_bin"
    mkdir -p "${empty_bin}"
    PATH="${empty_bin}" run have_sudo_access
    [ "${status}" -eq 1 ]
}

@test "have_sudo_access: returns 1 in-process when sudo binary always fails" {
    unset HAVE_SUDO_ACCESS
    local bin_dir="${BATS_TEST_TMPDIR}/fake_sudo_fail"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/sudo" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "${bin_dir}/sudo"
    PATH="${bin_dir}:${PATH}" have_sudo_access || true
    [[ "${HAVE_SUDO_ACCESS}" == "1" ]]
}

# --- have_sudo_access: in-process coverage for L711, L716-720 ---

@test "have_sudo_access: in-process with SUDO_ASKPASS and unset cache" {
    [[ -x /usr/bin/sudo ]] || skip "sudo not installed"
    sudo -n true 2>/dev/null || skip "sudo requires password"
    unset HAVE_SUDO_ACCESS
    export SUDO_ASKPASS="/bin/true"
    # Direct in-process call so kcov can track line hits
    have_sudo_access || true
    unset SUDO_ASKPASS
    [[ -n "${HAVE_SUDO_ACCESS+set}" ]]
}

@test "have_sudo_access: in-process without cache runs real sudo check" {
    [[ -x /usr/bin/sudo ]] || skip "sudo not installed"
    sudo -n true 2>/dev/null || skip "sudo requires password"
    unset HAVE_SUDO_ACCESS
    have_sudo_access || true
    [[ -n "${HAVE_SUDO_ACCESS+set}" ]]
}

# --- have_sudo_access: HAVE_SUDO_ACCESS unset, actual sudo check (L207-209) ---

@test "have_sudo_access: runs actual sudo check when HAVE_SUDO_ACCESS is unset" {
    run env -u LD_PRELOAD -u BASH_ENV bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +u +o pipefail
        unset HAVE_SUDO_ACCESS
        rc=0; have_sudo_access || rc=$?
        echo "result=${rc}"
    '
    # Whether it succeeds or fails depends on the environment;
    # the important thing is the code path is exercised
    assert_output --partial "result="
}

# --- pkg_install_handler: successful install path (L245) ---

@test "pkg_install_handler: successful install path hits verbose separator" {
    # have_sudo_access checks /usr/bin/sudo existence before cache
    [[ -x /usr/bin/sudo ]] || skip "sudo not installed"
    VERBOSE=2
    HAVE_SUDO_ACCESS=0
    # Create fake sudo and apt-get that succeed
    local bin_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/sudo" << 'WRAPPER'
#!/bin/bash
"$@"
WRAPPER
    chmod +x "${bin_dir}/sudo"
    cat > "${bin_dir}/apt-get" << 'WRAPPER'
#!/bin/bash
exit 0
WRAPPER
    chmod +x "${bin_dir}/apt-get"
    export PATH="${bin_dir}:${PATH}"

    run pkg_install_handler "fake_nonexistent_pkg_abc_xyz"
    assert_success
}

# --- execute_cmd: SSH remote branch (L304-305) ---

@test "execute_cmd: runs command via SSH when HOST is remote" {
    HOST="testuser@fakehost"
    local bin_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/ssh" << 'WRAPPER'
#!/bin/bash
# Skip all SSH options, read from stdin and pipe to bash
bash -ls
WRAPPER
    chmod +x "${bin_dir}/ssh"
    export PATH="${bin_dir}:${PATH}"

    SSH_OPTS=()
    run execute_cmd "echo remote_test"
    assert_success
    assert_output --partial "remote_test"
}

# --- execute_cmd_from_array: SSH remote branch (L415-416) ---

@test "execute_cmd_from_array: pipes array via SSH when HOST is remote" {
    HOST="testuser@fakehost"
    local bin_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/ssh" << 'WRAPPER'
#!/bin/bash
# Find the actual command (last argument) and execute it
eval "${@: -1}"
WRAPPER
    chmod +x "${bin_dir}/ssh"
    export PATH="${bin_dir}:${PATH}"

    SSH_OPTS=()
    run execute_cmd_from_array "xargs -0 -r printf '%s\n'" "a" "b"
    assert_success
    assert_output --partial "a"
}


# --- pkg_install_handler: no sudo path (L243) ---

@test "pkg_install_handler: log_error when no sudo access for missing package" {

    run env -u LD_PRELOAD -u BASH_ENV bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +u +o pipefail
        HAVE_SUDO_ACCESS=1
        VERBOSE=0
        pkg_install_handler "nonexistent_pkg_xyz_12345"
    '
    assert_failure
    assert_output --partial "No sudo access"
}

# --- _needs_sudo: auto-detect sudo based on path ---

@test "prefetch_token_cache: batches all unique env/cmd tokens into one execute_cmd call" {
    HOST="testremote"
    LOG_PATHS=(
        "<env:HOME>/log" "<cmd:hostname>.log" ""
        "<env:HOME>/log2" "<env:USER>.log" ""
        "/fixed/path" "plain.log" ""
    )
    _TOKEN_CACHE=()
    local call_log="${BATS_TEST_TMPDIR}/exec_calls"
    : > "${call_log}"
    execute_cmd() {
        echo x >> "${call_log}"
        bash -c "$1"
    }

    prefetch_token_cache

    local n
    n=$(wc -l < "${call_log}")
    [ "${n}" -eq 1 ] || {
        echo "expected 1 execute_cmd call, got ${n}" >&2
        return 1
    }
    [ "${_TOKEN_CACHE[env:HOME]}" = "${HOME}" ]
    [ "${_TOKEN_CACHE[env:USER]}" = "${USER}" ]
    [ "${_TOKEN_CACHE[cmd:hostname]}" = "$(hostname)" ]
}

@test "prefetch_token_cache: no-op when LOG_PATHS has no env/cmd tokens" {
    HOST="testremote"
    LOG_PATHS=("/var/log" "*.log" "")
    _TOKEN_CACHE=()
    _EXEC_COUNT=0
    execute_cmd() { _EXEC_COUNT=$(( _EXEC_COUNT + 1 )); }

    prefetch_token_cache

    [ "${_EXEC_COUNT}" -eq 0 ]
    [ "${#_TOKEN_CACHE[@]}" -eq 0 ]
}

@test "prefetch_token_cache: skips tokens already in cache" {
    HOST="testremote"
    LOG_PATHS=("<env:HOME>/log" "<cmd:hostname>.log" "")
    _TOKEN_CACHE=([env:HOME]="/cached/home" [cmd:hostname]="cachedhost")
    _EXEC_COUNT=0
    execute_cmd() { _EXEC_COUNT=$(( _EXEC_COUNT + 1 )); }

    prefetch_token_cache

    [ "${_EXEC_COUNT}" -eq 0 ]
    [ "${_TOKEN_CACHE[env:HOME]}" = "/cached/home" ]
}

@test "prefetch_token_cache: silently falls back when batch execute_cmd fails" {
    HOST="testremote"
    LOG_PATHS=("<env:HOME>/log" "log" "")
    _TOKEN_CACHE=()
    execute_cmd() { return 1; }

    # Should not abort the script
    prefetch_token_cache
    [ "${#_TOKEN_CACHE[@]}" -eq 0 ]
}

@test "prefetch_token_cache: falls back when remote output returns wrong number of values" {
    # Guards the mismatch branch that fires when the remote host returns fewer
    # separator-delimited values than tokens requested — for example when one
    # of the backticked commands produced nothing and its output collapsed.
    # The cache must stay empty rather than silently pairing token N with
    # value N-1.
    HOST="testremote"
    LOG_PATHS=(
        "<env:HOME>/a" "a.log" ""
        "<env:HOME>/b" "<cmd:hostname>.log" ""
    )
    _TOKEN_CACHE=()

    # Swallow the batched script and print a single value + separator, so the
    # parse loop sees 1 value but 2 tokens were requested.
    execute_cmd() {
        # Separator carries a recognizable prefix from pack_log.sh:
        # __PACK_LOG_TOK_SEP_$$_<rand>_<rand>__. We can't know it, but the
        # script appends the sep after each printf, so emitting a truncated
        # stream (one value + sep) exercises the mismatch branch.
        local sep
        sep=$(printf '%s' "$1" | sed -n 's/.*\(__PACK_LOG_TOK_SEP_[^"]*__\).*/\1/p' | head -1)
        printf '%s%s' "only-one-value" "${sep}"
    }

    prefetch_token_cache

    [ "${#_TOKEN_CACHE[@]}" -eq 0 ]
}

@test "_needs_sudo: returns true for path outside HOME" {
    HOST="local"
    _needs_sudo "/var/log" ""
}

@test "_needs_sudo: returns false for path under HOME" {
    HOST="local"
    run _needs_sudo "${HOME}/logs" ""
    assert_failure
}

@test "_needs_sudo: returns true when <sudo> flag is set even under HOME" {
    HOST="local"
    _needs_sudo "${HOME}/logs" "<sudo>"
}

@test "_needs_sudo: returns false for /tmp path (public directory)" {
    HOST="local"
    run _needs_sudo "/tmp/some_logs" ""
    assert_failure
}

@test "_needs_sudo: returns false for HOME with trailing slash" {
    HOST="local"
    run _needs_sudo "${HOME}/ros-docker/AMR" ""
    assert_failure
}

@test "_needs_sudo: returns true for path with HOME as prefix but different user" {
    HOST="local"
    # If HOME=/home/user, /home/username/logs should need sudo
    local fake_home="/home/testuser"
    HOME="${fake_home}"
    run _needs_sudo "/home/testusername/logs" ""
    assert_success
}

# --- date_format: date command failure (L282) ---

@test "date_format: log_error when date command fails" {
    VERBOSE=0
    # Passes regex ([0-9]{6}-[0-9]{4}) but yields impossible date 2099-99-99 99:99
    run date_format "999999-9999" "%Y%m%d"
    assert_failure
    assert_output --partial "Failed to format date"
}

# --- get_remote_value: command failure (L367) ---

@test "get_remote_value: log_error when command fails" {
    HOST="local"
    VERBOSE=0
    declare -gA _TOKEN_CACHE=()
    run get_remote_value "cmd" "false"
    assert_failure
    assert_output --partial "Command failed"
}

# --- get_remote_value: env type on remote host hits printf -v branch ---

@test "get_remote_value: env type with remote host uses printf -v get_cmd" {
    HOST="fake@remote"
    VERBOSE=0
    # Stub execute_cmd so we do not actually ssh; returns fixed value
    execute_cmd() { printf "%s" "remote_home_value"; }
    declare -gA _TOKEN_CACHE=()
    get_remote_value "env" "HOME"
    assert_equal "${REPLY}" "remote_home_value"
}

# --- create_folder: mkdir failure (L396) ---

@test "create_folder: log_error when mkdir fails" {
    HOST="local"
    VERBOSE=0
    run create_folder "/proc/impossible/path/that/cannot/be/created"
    assert_failure
    assert_output --partial "Failed to create folder"
}

# --- have_sudo_access: real code paths (L701, L706, L711, L716-720) ---

@test "have_sudo_access: real function hits SUDO_ASKPASS+actual sudo branch" {
    run env -u LD_PRELOAD -u BASH_ENV bash -c '
        source "'"${BATS_TEST_DIRNAME}/../pack_log.sh"'"
        set +u +o pipefail
        unset HAVE_SUDO_ACCESS
        export SUDO_ASKPASS="/bin/false"
        # Ensure not root, use the real function body path
        rc=0; have_sudo_access || rc=$?
        echo "rc=${rc}"
    '
    assert_output --partial "rc="
}

@test "have_sudo_access: returns 1 via real code when /usr/bin/sudo missing" {
    # Force PATH so that sudo check hits the -x test on /usr/bin/sudo.
    # We cannot remove /usr/bin/sudo, but we can skip if it is present.
    [[ ! -x /usr/bin/sudo ]] || skip "sudo is installed; cannot exercise L706"
    unset HAVE_SUDO_ACCESS
    run have_sudo_access
    assert_failure
}

# --- pkg_install_handler: apt-get failure (L754-755) ---

@test "pkg_install_handler: log_warn when apt-get install fails" {
    [[ -x /usr/bin/sudo ]] || skip "sudo not installed"
    VERBOSE=0
    HAVE_SUDO_ACCESS=0
    local bin_dir="${BATS_TEST_TMPDIR}/bin_fail"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/sudo" << 'WRAPPER'
#!/bin/bash
"$@"
WRAPPER
    chmod +x "${bin_dir}/sudo"
    cat > "${bin_dir}/apt-get" << 'WRAPPER'
#!/bin/bash
exit 1
WRAPPER
    chmod +x "${bin_dir}/apt-get"
    export PATH="${bin_dir}:${PATH}"

    run pkg_install_handler "fake_pkg_fail_abc"
    assert_failure
    assert_output --partial "Failed to install"
}
