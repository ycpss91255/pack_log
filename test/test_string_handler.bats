#!/usr/bin/env bats

setup() {
    load 'test_helper'
    HOST="local"
}

# =============================================================================
# special_string_parser
# =============================================================================

# --- env type ---

@test "special_string_parser: env type resolves environment variable" {
    special_string_parser "env:HOME"
    [[ "$REPLY_TYPE" == "env" ]]
    [[ "$REPLY_STR" == "$HOME" ]]
}

@test "special_string_parser: env type resolves USER variable" {
    special_string_parser "env:USER"
    [[ "$REPLY_TYPE" == "env" ]]
    [[ "$REPLY_STR" == "$USER" ]]
}

# --- cmd type ---

@test "special_string_parser: cmd type resolves command output" {
    special_string_parser "cmd:hostname"
    [[ "$REPLY_TYPE" == "cmd" ]]
    [[ "$REPLY_STR" == "$(hostname)" ]]
}

@test "special_string_parser: cmd type resolves echo command" {
    special_string_parser "cmd:echo hello"
    [[ "$REPLY_TYPE" == "cmd" ]]
    [[ "$REPLY_STR" == "hello" ]]
}

# --- date type ---

@test "special_string_parser: date type sets string directly without remote call" {
    special_string_parser "date:%Y%m%d"
    [[ "$REPLY_TYPE" == "date" ]]
    [[ "$REPLY_STR" == "%Y%m%d" ]]
}

@test "special_string_parser: date type with complex format" {
    special_string_parser "date:%Y%m%d-%H%M%S"
    [[ "$REPLY_TYPE" == "date" ]]
    [[ "$REPLY_STR" == "%Y%m%d-%H%M%S" ]]
}

# --- suffix type ---

@test "special_string_parser: suffix type sets string directly" {
    special_string_parser "suffix:.dat"
    [[ "$REPLY_TYPE" == "suffix" ]]
    [[ "$REPLY_STR" == ".dat" ]]
}

@test "special_string_parser: suffix type with pcd extension" {
    special_string_parser "suffix:.pcd"
    [[ "$REPLY_TYPE" == "suffix" ]]
    [[ "$REPLY_STR" == ".pcd" ]]
}

# --- unknown type ---

@test "special_string_parser: unknown type causes error exit" {
    run special_string_parser "unknown:value"
    assert_failure 1
    assert_output --partial "Unknown special string type: unknown"
}

# --- invalid format (no colon) ---

@test "special_string_parser: missing colon causes error exit" {
    run special_string_parser "nocolon"
    assert_failure 1
    assert_output --partial "Invalid special string format: nocolon"
}

# --- missing arguments ---

@test "special_string_parser: missing all arguments causes error exit" {
    run special_string_parser
    assert_failure
}

# =============================================================================
# string_handler
# =============================================================================

# --- env token ---

@test "string_handler: resolves env:HOME token in path" {
    string_handler "<env:HOME>/some/path" "logfile"
    [[ "$REPLY_PATH" == "$HOME/some/path" ]]
    [[ "$REPLY_PREFIX" == "logfile" ]]
    [[ "$REPLY_SUFFIX" == "" ]]
}

# --- cmd token ---

@test "string_handler: resolves cmd:hostname token in prefix" {
    local expected_hostname
    expected_hostname="$(hostname)"
    string_handler "/var/log" "app.${expected_hostname}.log"
    [[ "$REPLY_PATH" == "/var/log" ]]
    [[ "$REPLY_PREFIX" == "app.${expected_hostname}.log" ]]
}

@test "string_handler: resolves cmd:hostname token via special format" {
    local expected_hostname
    expected_hostname="$(hostname)"
    string_handler "/var/log" "app.<cmd:hostname>.log"
    [[ "$REPLY_PATH" == "/var/log" ]]
    [[ "$REPLY_PREFIX" == "app.${expected_hostname}.log" ]]
}

# --- suffix token ---

@test "string_handler: extracts suffix token and removes it from string" {
    string_handler "/data" "files*<suffix:.dat>"
    [[ "$REPLY_PATH" == "/data" ]]
    [[ "$REPLY_PREFIX" == "files*" ]]
    [[ "$REPLY_SUFFIX" == ".dat" ]]
}

# --- date token ---

@test "string_handler: keeps date token as-is for later processing" {
    string_handler "/logs" "app_<date:%Y%m%d>*"
    [[ "$REPLY_PATH" == "/logs" ]]
    [[ "$REPLY_PREFIX" == "app_<date:%Y%m%d>*" ]]
    [[ "$REPLY_SUFFIX" == "" ]]
}

@test "string_handler: date token with complex format is preserved" {
    string_handler "/logs" "app_<date:%Y%m%d-%H%M%S>*"
    [[ "$REPLY_PATH" == "/logs" ]]
    [[ "$REPLY_PREFIX" == "app_<date:%Y%m%d-%H%M%S>*" ]]
}

# --- multiple tokens combined ---

@test "string_handler: resolves env and keeps date token together" {
    string_handler "<env:HOME>/logs" "app_<date:%Y%m%d>*"
    [[ "$REPLY_PATH" == "$HOME/logs" ]]
    [[ "$REPLY_PREFIX" == "app_<date:%Y%m%d>*" ]]
    [[ "$REPLY_SUFFIX" == "" ]]
}

@test "string_handler: resolves env, keeps date, and extracts suffix" {
    string_handler "<env:HOME>/data" "file_<date:%Y%m%d>*<suffix:.log>"
    [[ "$REPLY_PATH" == "$HOME/data" ]]
    [[ "$REPLY_PREFIX" == "file_<date:%Y%m%d>*" ]]
    [[ "$REPLY_SUFFIX" == ".log" ]]
}

@test "string_handler: multiple env and cmd tokens resolved" {
    local expected_hostname
    expected_hostname="$(hostname)"
    string_handler "<env:HOME>/log_core" "corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*"
    [[ "$REPLY_PATH" == "$HOME/log_core" ]]
    [[ "$REPLY_PREFIX" == "corenavi_auto.${expected_hostname}.${USER}.log.INFO.<date:%Y%m%d-%H%M%S>*" ]]
    [[ "$REPLY_SUFFIX" == "" ]]
}

# --- path::file format ---

@test "string_handler: splits path and prefix on double colon" {
    string_handler "/var/log/app" "server.log"
    [[ "$REPLY_PATH" == "/var/log/app" ]]
    [[ "$REPLY_PREFIX" == "server.log" ]]
    [[ "$REPLY_SUFFIX" == "" ]]
}

# --- no special tokens ---

@test "string_handler: plain string with no tokens splits correctly" {
    string_handler "/home/user/logs" "output.txt"
    [[ "$REPLY_PATH" == "/home/user/logs" ]]
    [[ "$REPLY_PREFIX" == "output.txt" ]]
    [[ "$REPLY_SUFFIX" == "" ]]
}

@test "string_handler: plain string with wildcard prefix" {
    string_handler "/home/user/logs" "*"
    [[ "$REPLY_PATH" == "/home/user/logs" ]]
    [[ "$REPLY_PREFIX" == "*" ]]
    [[ "$REPLY_SUFFIX" == "" ]]
}

# --- complex real-world path ---

@test "string_handler: complex real-world lidar detection path" {
    string_handler '<env:HOME>/ros-docker/AMR/myuser/log_data/lidar_detection' 'detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*<suffix:.dat>'
    [[ "$REPLY_PATH" == "$HOME/ros-docker/AMR/myuser/log_data/lidar_detection" ]]
    [[ "$REPLY_PREFIX" == "detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*" ]]
    [[ "$REPLY_SUFFIX" == ".dat" ]]
}

@test "string_handler: complex real-world slam log path" {
    string_handler '<env:HOME>/ros-docker/AMR/myuser/log_slam' 'coreslam_2D_<date:%s>*<suffix:.log>'
    [[ "$REPLY_PATH" == "$HOME/ros-docker/AMR/myuser/log_slam" ]]
    [[ "$REPLY_PREFIX" == "coreslam_2D_<date:%s>*" ]]
    [[ "$REPLY_SUFFIX" == ".log" ]]
}

@test "string_handler: complex real-world glog path with no suffix" {
    string_handler '<env:HOME>/ros-docker/AMR/myuser/log_data/lidar_detection/glog' 'detect_shelf_node-DetectShelf-<date:%Y%m%d-%H%M%S>*'
    [[ "$REPLY_PATH" == "$HOME/ros-docker/AMR/myuser/log_data/lidar_detection/glog" ]]
    [[ "$REPLY_PREFIX" == "detect_shelf_node-DetectShelf-<date:%Y%m%d-%H%M%S>*" ]]
    [[ "$REPLY_SUFFIX" == "" ]]
}

@test "string_handler: config file with no date or suffix tokens" {
    string_handler '<env:HOME>/ros-docker/AMR/myuser/core_storage' 'node_config.yaml'
    [[ "$REPLY_PATH" == "$HOME/ros-docker/AMR/myuser/core_storage" ]]
    [[ "$REPLY_PREFIX" == "node_config.yaml" ]]
    [[ "$REPLY_SUFFIX" == "" ]]
}

# =============================================================================
# <num> and <name> tokens
# =============================================================================

@test "string_handler: <num> token resolves to host number" {
    NUM="7"
    string_handler '/home/user/logs_#<num>' '*'
    [[ "$REPLY_PATH" == "/home/user/logs_#7" ]]
    [[ "$REPLY_PREFIX" == "*" ]]
}

@test "string_handler: <name> token resolves to host display name" {
    NUM="1"
    string_handler '/home/user/logs_<name>' '*'
    [[ "$REPLY_PATH" == "/home/user/logs_${HOSTS[0]%%::*}" ]]
    [[ "$REPLY_PREFIX" == "*" ]]
}

@test "string_handler: <num> and <name> combined with other tokens" {
    NUM="3"
    string_handler '<env:HOME>/logs_<name>_#<num>' '*.log'
    local expected_name="${HOSTS[2]%%::*}"
    [[ "$REPLY_PATH" == "$HOME/logs_${expected_name}_#3" ]]
    [[ "$REPLY_PREFIX" == "*.log" ]]
}

@test "string_handler: <num> warns and is removed when NUM is empty" {
    NUM=""
    run string_handler '/home/user/logs_#<num>' '*'
    assert_success
    assert_output --partial "requires -n"
}

@test "string_handler: <name> warns and is removed when NUM is empty" {
    NUM=""
    run string_handler '/home/user/logs_<name>' '*'
    assert_success
    assert_output --partial "requires -n"
}

@test "string_handler: <num> warns when using -u (no NUM)" {
    NUM=""
    HOST="myuser@10.0.0.1"
    run string_handler '/home/user/corenavi_#<num>' '*'
    assert_success
    assert_output --partial "requires -n"
}

# =============================================================================
# resolve_path_dates
# =============================================================================

@test "resolve_path_dates: resolves date token in path portion" {
    START_TIME="260309-0000"
    END_TIME="260309-2359"
    REPLY_PATH="/home/user/corenavi_<date:%m%d>_test"
    resolve_path_dates
    [[ "${#REPLY_PATHS[@]}" -eq 1 ]]
    [[ "${REPLY_PATHS[0]}" == "/home/user/corenavi_0309_test" ]]
}

@test "resolve_path_dates: leaves path without date tokens unchanged" {
    START_TIME="260309-0000"
    END_TIME="260309-2359"
    REPLY_PATH="/home/user/plain_path"
    resolve_path_dates
    [[ "${#REPLY_PATHS[@]}" -eq 1 ]]
    [[ "${REPLY_PATHS[0]}" == "/home/user/plain_path" ]]
}

@test "resolve_path_dates: expands cross-date paths" {
    START_TIME="260115-0000"
    END_TIME="260117-2359"
    REPLY_PATH="/home/user/log/AvoidStop_<date:%Y-%m-%d>"
    resolve_path_dates
    [[ "${#REPLY_PATHS[@]}" -eq 3 ]]
    [[ "${REPLY_PATHS[0]}" == "/home/user/log/AvoidStop_2026-01-15" ]]
    [[ "${REPLY_PATHS[1]}" == "/home/user/log/AvoidStop_2026-01-16" ]]
    [[ "${REPLY_PATHS[2]}" == "/home/user/log/AvoidStop_2026-01-17" ]]
}

@test "resolve_path_dates: batches date invocations across multi-day range" {
    START_TIME="260101-0000"
    END_TIME="260110-2359"
    REPLY_PATH="/var/log/AvoidStop_<date:%Y-%m-%d>"

    # Wrap `date` to count invocations. date_format uses `date` twice
    # (start/end epoch); resolve_path_dates should add ONE more batched call,
    # not one per day. Total expected: <= 4 (cushion for date_format internals).
    : > "${BATS_TEST_TMPDIR}/date_calls"
    date() {
        printf 'x\n' >> "${BATS_TEST_TMPDIR}/date_calls"
        command date "$@"
    }

    resolve_path_dates

    unset -f date

    assert_equal "${#REPLY_PATHS[@]}" 10
    [[ "${REPLY_PATHS[0]}" == "/var/log/AvoidStop_2026-01-01" ]]
    [[ "${REPLY_PATHS[9]}" == "/var/log/AvoidStop_2026-01-10" ]]
    local n
    n=$(wc -l < "${BATS_TEST_TMPDIR}/date_calls")
    [[ "${n}" -le 4 ]] || { echo "date called ${n} times (expected <=4)"; false; }
}

@test "resolve_path_dates: combined <num> and <date:> in path" {
    NUM="7"
    START_TIME="260309-0000"
    END_TIME="260309-2359"
    string_handler '/home/user/corenavi_<date:%m%d>_#<num>' 'app.<date:%Y%m%d-%H%M%S>*.log'
    resolve_path_dates
    [[ "${#REPLY_PATHS[@]}" -eq 1 ]]
    [[ "${REPLY_PATHS[0]}" == "/home/user/corenavi_0309_#7" ]]
    [[ "$REPLY_PREFIX" == "app.<date:%Y%m%d-%H%M%S>*.log" ]]
}
