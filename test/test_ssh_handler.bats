#!/usr/bin/env bats

setup() {
    load 'test_helper'
    VERBOSE=0
    HOST="myuser@192.168.1.100"

    # Use temp SSH key path so we don't touch real keys
    SSH_KEY="${BATS_TEST_TMPDIR}/test_ssh_key"
    SSH_TIMEOUT=3

    # Rebuild SSH_OPTS to reference the temp SSH_KEY
    SSH_OPTS=(
        -i "${SSH_KEY}"
        -o BatchMode=yes
        -o ConnectTimeout="${SSH_TIMEOUT}"
        -o NumberOfPasswordPrompts=0
        -o PreferredAuthentications=publickey
        -o StrictHostKeyChecking=no
    )

    # Ensure .ssh directory exists for known_hosts tests
    mkdir -p "${HOME}/.ssh"

    # Save original function definitions for restoration
    _orig_execute_cmd=$(declare -f execute_cmd)
    _orig_pkg_install_handler=$(declare -f pkg_install_handler)
}

teardown() {
    # Restore original functions
    eval "${_orig_execute_cmd}"
    eval "${_orig_pkg_install_handler}"
}

# Helper: create a fake SSH key pair in BATS_TEST_TMPDIR
_create_fake_ssh_key() {
    ssh-keygen -t ed25519 -f "${SSH_KEY}" -N "" -q 2>/dev/null
}

# Helper: mock execute_cmd that fails for the first N calls, then succeeds.
# Uses a file counter because execute_cmd is called inside $() subshells,
# which prevents variable-based counters from persisting.
_mock_execute_cmd_fail_then_succeed() {
    local fail_count="${1:-1}"
    local fail_msg="${2:-Connection refused}"
    local counter_file="${BATS_TEST_TMPDIR}/exec_counter"
    echo "0" > "${counter_file}"

    execute_cmd() {
        local c
        c=$(cat "${BATS_TEST_TMPDIR}/exec_counter")
        c=$((c + 1))
        echo "${c}" > "${BATS_TEST_TMPDIR}/exec_counter"
        if [[ ${c} -le FAIL_COUNT_PLACEHOLDER ]]; then
            echo "FAIL_MSG_PLACEHOLDER" >&2
            return 1
        fi
        return 0
    }
    # Patch placeholders with actual values (avoids closure issues)
    local func_body
    func_body=$(declare -f execute_cmd)
    func_body="${func_body//FAIL_COUNT_PLACEHOLDER/${fail_count}}"
    func_body="${func_body//FAIL_MSG_PLACEHOLDER/${fail_msg}}"
    eval "${func_body}"
}

# ---------------------------------------------------------------------------
# 1. pkg_install_handler is called for "ssh"
# ---------------------------------------------------------------------------

@test "ssh_handler: calls pkg_install_handler for ssh" {
    local pkg_called=""

    # Override pkg_install_handler to record the call
    pkg_install_handler() {
        pkg_called="$1"
        return 0
    }

    # Override execute_cmd to succeed immediately
    execute_cmd() { return 0; }

    ssh_handler
    [[ "${pkg_called}" == "ssh" ]]
}

@test "ssh_handler: exits if pkg_install_handler fails" {
    pkg_install_handler() { return 1; }

    run ssh_handler
    assert_failure
}

# ---------------------------------------------------------------------------
# 2. SSH connection succeeds on first try
# ---------------------------------------------------------------------------

@test "ssh_handler: returns 0 when SSH connection succeeds on first try" {
    _create_fake_ssh_key

    pkg_install_handler() { return 0; }
    execute_cmd() { return 0; }

    run ssh_handler
    assert_success
}

# ---------------------------------------------------------------------------
# 3. SSH key doesn't exist -> creates key and copies
# ---------------------------------------------------------------------------

@test "ssh_handler: creates SSH key when it does not exist" {
    # Ensure no key exists
    rm -f "${SSH_KEY}" "${SSH_KEY}.pub"

    pkg_install_handler() { return 0; }

    # First call to execute_cmd fails (connection test), second succeeds (after key setup)
    _mock_execute_cmd_fail_then_succeed 1 "Connection refused"

    # We need ssh-keygen and ssh-copy-id to work.
    # Create real key pair since ssh-keygen is available in test env
    # But wrap ssh-copy-id to avoid actual network calls.

    # Create a wrapper for ssh-copy-id in PATH
    local bin_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/ssh-copy-id" << 'WRAPPER'
#!/bin/bash
exit 0
WRAPPER
    chmod +x "${bin_dir}/ssh-copy-id"
    export PATH="${bin_dir}:${PATH}"

    run ssh_handler
    assert_success

    # Verify that the key was created
    [[ -f "${SSH_KEY}" ]]
    [[ -f "${SSH_KEY}.pub" ]]
}

# ---------------------------------------------------------------------------
# 4. Permission denied -> copies key
# ---------------------------------------------------------------------------

@test "ssh_handler: copies key on Permission denied error" {
    _create_fake_ssh_key

    pkg_install_handler() { return 0; }

    _mock_execute_cmd_fail_then_succeed 1 "Permission denied (publickey)"

    # Stub ssh-copy-id
    local bin_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/ssh-copy-id" << 'WRAPPER'
#!/bin/bash
exit 0
WRAPPER
    chmod +x "${bin_dir}/ssh-copy-id"
    export PATH="${bin_dir}:${PATH}"

    run ssh_handler
    assert_success
}

# ---------------------------------------------------------------------------
# 5. Host key verification failed -> removes and re-adds host key
# ---------------------------------------------------------------------------

@test "ssh_handler: handles Host key verification failed" {
    _create_fake_ssh_key

    pkg_install_handler() { return 0; }

    _mock_execute_cmd_fail_then_succeed 1 "Host key verification failed"

    # Stub ssh-keygen -F, -R, and ssh-keyscan to avoid real network calls
    local bin_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bin_dir}"

    # Wrapper for ssh-keygen that handles -F and -R but passes through others
    cat > "${bin_dir}/ssh-keygen" << WRAPPER
#!/bin/bash
case "\$1" in
    -F) exit 0 ;;    # Pretend host is found in known_hosts
    -R) exit 0 ;;    # Pretend removal succeeded
    *)  /usr/bin/ssh-keygen "\$@" ;;  # Pass through for key generation
esac
WRAPPER
    chmod +x "${bin_dir}/ssh-keygen"

    cat > "${bin_dir}/ssh-keyscan" << 'WRAPPER'
#!/bin/bash
echo "192.168.1.100 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest"
WRAPPER
    chmod +x "${bin_dir}/ssh-keyscan"

    export PATH="${bin_dir}:${PATH}"

    run ssh_handler
    assert_success
}

@test "ssh_handler: handles REMOTE HOST IDENTIFICATION HAS CHANGED" {
    _create_fake_ssh_key

    pkg_install_handler() { return 0; }

    _mock_execute_cmd_fail_then_succeed 1 "REMOTE HOST IDENTIFICATION HAS CHANGED!"

    local bin_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bin_dir}"

    cat > "${bin_dir}/ssh-keygen" << WRAPPER
#!/bin/bash
case "\$1" in
    -F) exit 0 ;;
    -R) exit 0 ;;
    *)  /usr/bin/ssh-keygen "\$@" ;;
esac
WRAPPER
    chmod +x "${bin_dir}/ssh-keygen"

    cat > "${bin_dir}/ssh-keyscan" << 'WRAPPER'
#!/bin/bash
echo "192.168.1.100 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest"
WRAPPER
    chmod +x "${bin_dir}/ssh-keyscan"

    export PATH="${bin_dir}:${PATH}"

    run ssh_handler
    assert_success
}

# ---------------------------------------------------------------------------
# 6. Unknown SSH error -> exits with error
# ---------------------------------------------------------------------------

@test "ssh_handler: exits on unknown SSH error" {
    _create_fake_ssh_key

    pkg_install_handler() { return 0; }

    execute_cmd() {
        echo "Network is unreachable" >&2
        return 1
    }

    run ssh_handler
    assert_failure
    assert_output --partial "SSH connection failed: Network is unreachable"
}

# ---------------------------------------------------------------------------
# 7. All retries exhausted -> exits with error
# ---------------------------------------------------------------------------

@test "ssh_handler: exits after max retries exhausted" {
    # No key exists - every attempt will try to create key + copy, then fail
    rm -f "${SSH_KEY}" "${SSH_KEY}.pub"

    pkg_install_handler() { return 0; }

    # Always fail with Permission denied (a recognized error that triggers retry)
    execute_cmd() {
        echo "Permission denied (publickey)" >&2
        return 1
    }

    # Stub ssh-keygen and ssh-copy-id so they "work" but connection still fails
    local bin_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bin_dir}"

    cat > "${bin_dir}/ssh-keygen" << WRAPPER
#!/bin/bash
case "\$1" in
    -t)
        # Create dummy key files
        touch "\$4" "\$4.pub"
        # Write minimal key content for the pub key match check
        echo "ssh-ed25519 AAAA fake-key" > "\$4.pub"
        exit 0
        ;;
    -y)
        echo "ssh-ed25519 AAAA"
        exit 0
        ;;
    *)  exit 0 ;;
esac
WRAPPER
    chmod +x "${bin_dir}/ssh-keygen"

    cat > "${bin_dir}/ssh-copy-id" << 'WRAPPER'
#!/bin/bash
exit 0
WRAPPER
    chmod +x "${bin_dir}/ssh-copy-id"

    export PATH="${bin_dir}:${PATH}"

    run ssh_handler
    assert_failure
    assert_output --partial "SSH connection failed after 3 retries"
}

# ---------------------------------------------------------------------------
# 8. SSH key creation: ed25519 first, falls back to rsa
# ---------------------------------------------------------------------------

@test "ssh_handler: falls back to rsa when ed25519 keygen fails" {
    rm -f "${SSH_KEY}" "${SSH_KEY}.pub"

    pkg_install_handler() { return 0; }

    _mock_execute_cmd_fail_then_succeed 1 "Connection refused"

    local bin_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bin_dir}"

    # ssh-keygen that fails for ed25519, succeeds for rsa
    cat > "${bin_dir}/ssh-keygen" << WRAPPER
#!/bin/bash
if [[ "\$1" == "-t" ]]; then
    if [[ "\$2" == "ed25519" ]]; then
        exit 1
    elif [[ "\$2" == "rsa" ]]; then
        /usr/bin/ssh-keygen -t rsa -f "\$4" -N "" -q 2>/dev/null
        exit 0
    fi
elif [[ "\$1" == "-y" ]]; then
    /usr/bin/ssh-keygen "\$@"
    exit \$?
fi
exit 0
WRAPPER
    chmod +x "${bin_dir}/ssh-keygen"

    cat > "${bin_dir}/ssh-copy-id" << 'WRAPPER'
#!/bin/bash
exit 0
WRAPPER
    chmod +x "${bin_dir}/ssh-copy-id"

    export PATH="${bin_dir}:${PATH}"

    run ssh_handler
    assert_success
    [[ -f "${SSH_KEY}" ]]
}

# ---------------------------------------------------------------------------
# 9. SSH key creation failure -> exits with error
# ---------------------------------------------------------------------------

@test "ssh_handler: exits when SSH key creation fails for all algorithms" {
    rm -f "${SSH_KEY}" "${SSH_KEY}.pub"

    pkg_install_handler() { return 0; }

    execute_cmd() {
        echo "Connection refused" >&2
        return 1
    }

    local bin_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bin_dir}"

    # ssh-keygen that always fails
    cat > "${bin_dir}/ssh-keygen" << 'WRAPPER'
#!/bin/bash
exit 1
WRAPPER
    chmod +x "${bin_dir}/ssh-keygen"

    export PATH="${bin_dir}:${PATH}"

    run ssh_handler
    assert_failure
    assert_output --partial "Failed to create SSH key"
}

# ---------------------------------------------------------------------------
# Retry exhaustion covering L690 (log_error after all retries)
# ---------------------------------------------------------------------------

@test "ssh_handler: exhausting retries hits log_error on line 690" {
    _create_fake_ssh_key

    pkg_install_handler() { return 0; }

    # Always fail with Permission denied to trigger retries
    execute_cmd() {
        echo "Permission denied (publickey)" >&2
        return 1
    }

    local bin_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bin_dir}"

    cat > "${bin_dir}/ssh-copy-id" << 'WRAPPER'
#!/bin/bash
exit 0
WRAPPER
    chmod +x "${bin_dir}/ssh-copy-id"

    cat > "${bin_dir}/ssh-keygen" << WRAPPER
#!/bin/bash
case "\$1" in
    -y) /usr/bin/ssh-keygen "\$@"; exit \$? ;;
    *)  /usr/bin/ssh-keygen "\$@" ;;
esac
WRAPPER
    chmod +x "${bin_dir}/ssh-keygen"

    export PATH="${bin_dir}:${PATH}"

    run ssh_handler
    assert_failure
    assert_output --partial "SSH connection failed after"
}

# ---------------------------------------------------------------------------
# 10. Host key not in known_hosts -> just adds via keyscan (no removal)
# ---------------------------------------------------------------------------

@test "ssh_handler: adds host key when not in known_hosts" {
    _create_fake_ssh_key

    pkg_install_handler() { return 0; }

    _mock_execute_cmd_fail_then_succeed 1 "Host key verification failed"

    local bin_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bin_dir}"

    # ssh-keygen -F returns 1 (host NOT found), so -R should not be called
    local keygen_r_called="${BATS_TEST_TMPDIR}/keygen_r_called"

    cat > "${bin_dir}/ssh-keygen" << WRAPPER
#!/bin/bash
case "\$1" in
    -F) exit 1 ;;    # Host NOT found in known_hosts
    -R) touch "${keygen_r_called}"; exit 0 ;;
    *)  /usr/bin/ssh-keygen "\$@" ;;
esac
WRAPPER
    chmod +x "${bin_dir}/ssh-keygen"

    cat > "${bin_dir}/ssh-keyscan" << 'WRAPPER'
#!/bin/bash
echo "192.168.1.100 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest"
WRAPPER
    chmod +x "${bin_dir}/ssh-keyscan"

    export PATH="${bin_dir}:${PATH}"

    run ssh_handler
    assert_success

    # ssh-keygen -R should NOT have been called since -F returned 1
    [[ ! -f "${keygen_r_called}" ]]
}
