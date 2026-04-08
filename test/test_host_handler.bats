#!/usr/bin/env bats

setup() {
    load 'test_helper'
    NUM=""
    HOST=""
    VERBOSE=0

    # Re-initialize HOSTS array (declare creates locals when sourced in function scope)
    HOSTS=(
        "pana01::myuser@10.90.68.188"
        "pana02::myuser@10.90.68.191"
        "pana03::myuser@10.90.68.15"
        "pana04::myuser@10.90.68.14"
        "pana05::myuser@10.90.69.16"
        "pana06::myuser@10.90.69.17"
        "pana07::myuser@10.90.69.101"
    )
}

# --- HOST="local" ---

@test "host_handler: HOST=local stays local and returns 0" {
    HOST="local"
    host_handler
    [[ "${HOST}" == "local" ]]
}

# --- NUM set to valid number ---

@test "host_handler: NUM=1 resolves HOST from HOSTS array" {
    NUM="1"
    host_handler
    [[ "${HOST}" == "myuser@10.90.68.188" ]]
}

@test "host_handler: NUM=2 resolves HOST from HOSTS array" {
    NUM="2"
    host_handler
    [[ "${HOST}" == "myuser@10.90.68.191" ]]
}

@test "host_handler: NUM set to last valid index resolves correctly" {
    NUM="${#HOSTS[@]}"
    host_handler
    local expected="${HOSTS[${#HOSTS[@]}-1]#*::}"
    [[ "${HOST}" == "${expected}" ]]
}

# --- NUM set to invalid number (too high) ---

@test "host_handler: NUM exceeding HOSTS length should error" {
    NUM="$(( ${#HOSTS[@]} + 1 ))"
    run host_handler
    assert_failure 1
    assert_output --partial "Number must be between 1 and ${#HOSTS[@]}"
}

@test "host_handler: NUM much larger than HOSTS length should error" {
    NUM="999"
    run host_handler
    assert_failure 1
    assert_output --partial "Number must be between 1 and"
}

# --- NUM set to invalid number (0 or negative) ---

@test "host_handler: NUM=0 should error with invalid format" {
    NUM="0"
    run host_handler
    assert_failure 1
    assert_output --partial "Invalid user@host format"
}

@test "host_handler: NUM=-1 should error with invalid format" {
    NUM="-1"
    run host_handler
    assert_failure 1
    assert_output --partial "Invalid user@host format"
}

# --- HOST set to valid user@host format ---

@test "host_handler: HOST=user@host passes validation" {
    HOST="testuser@192.168.1.1"
    host_handler
    [[ "${HOST}" == "testuser@192.168.1.1" ]]
}

@test "host_handler: HOST=user@hostname passes validation" {
    HOST="admin@myserver"
    host_handler
    [[ "${HOST}" == "admin@myserver" ]]
}

# --- HOST set to invalid format (no @) ---

@test "host_handler: HOST without @ should error" {
    HOST="invalidhost"
    run host_handler
    assert_failure 1
    assert_output --partial "Invalid user@host format: invalidhost"
}

@test "host_handler: HOST with spaces should error" {
    HOST="user @host"
    run host_handler
    assert_failure 1
    assert_output --partial "Invalid user@host format"
}


# --- Interactive mode: both NUM and HOST empty ---

@test "host_handler: interactive input 'local' sets HOST=local" {
    echo "local" | {
        host_handler
        [[ "${HOST}" == "local" ]]
    }
}

@test "host_handler: interactive input 'Local' (case-insensitive) sets HOST=local" {
    echo "Local" | {
        host_handler
        [[ "${HOST}" == "local" ]]
    }
}

@test "host_handler: interactive input 'LOCAL' (uppercase) sets HOST=local" {
    echo "LOCAL" | {
        host_handler
        [[ "${HOST}" == "local" ]]
    }
}

@test "host_handler: interactive input valid number resolves HOST from array" {
    echo "1" | {
        host_handler
        [[ "${HOST}" == "myuser@10.90.68.188" ]]
    }
}

@test "host_handler: interactive input user@host sets HOST directly" {
    echo "someone@10.0.0.1" | {
        host_handler
        [[ "${HOST}" == "someone@10.0.0.1" ]]
    }
}

@test "host_handler: interactive input invalid string should error" {
    NUM=""; HOST=""; VERBOSE=0
    run env -u LD_PRELOAD -u BASH_ENV bash -c 'echo "garbage" | { source "'"${BATS_TEST_DIRNAME}"'/../pack_log.sh"; NUM=""; HOST=""; VERBOSE=0; host_handler; }'
    assert_failure 1
    assert_output --partial "Invalid input: garbage"
}

@test "host_handler: interactive input empty string should error" {
    NUM=""; HOST=""; VERBOSE=0
    run env -u LD_PRELOAD -u BASH_ENV bash -c 'echo "" | { source "'"${BATS_TEST_DIRNAME}"'/../pack_log.sh"; NUM=""; HOST=""; VERBOSE=0; host_handler; }'
    assert_failure 1
    assert_output --partial "Invalid input"
}

@test "host_handler: invalid interactive input covers MSG_INVALID_INPUT in-process" {
    NUM=""; HOST=""; VERBOSE=0
    run host_handler <<< "garbage_xyz"
    assert_failure
    assert_output --partial "Invalid input"
}

# --- NUM is valid number, HOST is empty ---

@test "host_handler: NUM=3 with HOST empty resolves from array" {
    NUM="3"
    HOST=""
    host_handler
    [[ "${HOST}" == "myuser@10.90.68.15" ]]
}

@test "host_handler: NUM=7 with HOST empty resolves last entry" {
    NUM="7"
    HOST=""
    host_handler
    [[ "${HOST}" == "myuser@10.90.69.101" ]]
}
