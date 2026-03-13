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
    local out_type="" out_str=""
    special_string_parser "env:HOME" out_type out_str
    [[ "$out_type" == "env" ]]
    [[ "$out_str" == "$HOME" ]]
}

@test "special_string_parser: env type resolves USER variable" {
    local out_type="" out_str=""
    special_string_parser "env:USER" out_type out_str
    [[ "$out_type" == "env" ]]
    [[ "$out_str" == "$USER" ]]
}

# --- cmd type ---

@test "special_string_parser: cmd type resolves command output" {
    local out_type="" out_str=""
    special_string_parser "cmd:hostname" out_type out_str
    [[ "$out_type" == "cmd" ]]
    [[ "$out_str" == "$(hostname)" ]]
}

@test "special_string_parser: cmd type resolves echo command" {
    local out_type="" out_str=""
    special_string_parser "cmd:echo hello" out_type out_str
    [[ "$out_type" == "cmd" ]]
    [[ "$out_str" == "hello" ]]
}

# --- date type ---

@test "special_string_parser: date type sets string directly without remote call" {
    local out_type="" out_str=""
    special_string_parser "date:%Y%m%d" out_type out_str
    [[ "$out_type" == "date" ]]
    [[ "$out_str" == "%Y%m%d" ]]
}

@test "special_string_parser: date type with complex format" {
    local out_type="" out_str=""
    special_string_parser "date:%Y%m%d-%H%M%S" out_type out_str
    [[ "$out_type" == "date" ]]
    [[ "$out_str" == "%Y%m%d-%H%M%S" ]]
}

# --- suffix type ---

@test "special_string_parser: suffix type sets string directly" {
    local out_type="" out_str=""
    special_string_parser "suffix:.dat" out_type out_str
    [[ "$out_type" == "suffix" ]]
    [[ "$out_str" == ".dat" ]]
}

@test "special_string_parser: suffix type with pcd extension" {
    local out_type="" out_str=""
    special_string_parser "suffix:.pcd" out_type out_str
    [[ "$out_type" == "suffix" ]]
    [[ "$out_str" == ".pcd" ]]
}

# --- unknown type ---

@test "special_string_parser: unknown type causes error exit" {
    run special_string_parser "unknown:value" out_type out_str
    assert_failure 1
    assert_output --partial "Unknown special string type: unknown"
}

# --- invalid format (no colon) ---

@test "special_string_parser: missing colon causes error exit" {
    run special_string_parser "nocolon" out_type out_str
    assert_failure 1
    assert_output --partial "Invalid special string format: nocolon"
}

# --- missing arguments ---

@test "special_string_parser: missing all arguments causes error exit" {
    run special_string_parser
    assert_failure
}

@test "special_string_parser: missing type outvar causes error exit" {
    run special_string_parser "env:HOME"
    assert_failure
}

@test "special_string_parser: missing string outvar causes error exit" {
    run special_string_parser "env:HOME" out_type
    assert_failure
}

# =============================================================================
# string_handler
# =============================================================================

# --- env token ---

@test "string_handler: resolves env:HOME token in path" {
    local path="" prefix="" suffix=""
    string_handler "<env:HOME>/some/path::logfile" path prefix suffix
    [[ "$path" == "$HOME/some/path" ]]
    [[ "$prefix" == "logfile" ]]
    [[ "$suffix" == "" ]]
}

# --- cmd token ---

@test "string_handler: resolves cmd:hostname token in prefix" {
    local path="" prefix="" suffix=""
    local expected_hostname
    expected_hostname="$(hostname)"
    string_handler "/var/log::app.${expected_hostname}.log" path prefix suffix
    [[ "$path" == "/var/log" ]]
    [[ "$prefix" == "app.${expected_hostname}.log" ]]
}

@test "string_handler: resolves cmd:hostname token via special format" {
    local path="" prefix="" suffix=""
    local expected_hostname
    expected_hostname="$(hostname)"
    string_handler "/var/log::app.<cmd:hostname>.log" path prefix suffix
    [[ "$path" == "/var/log" ]]
    [[ "$prefix" == "app.${expected_hostname}.log" ]]
}

# --- suffix token ---

@test "string_handler: extracts suffix token and removes it from string" {
    local path="" prefix="" suffix=""
    string_handler "/data::files*<suffix:.dat>" path prefix suffix
    [[ "$path" == "/data" ]]
    [[ "$prefix" == "files*" ]]
    [[ "$suffix" == ".dat" ]]
}

# --- date token ---

@test "string_handler: keeps date token as-is for later processing" {
    local path="" prefix="" suffix=""
    string_handler "/logs::app_<date:%Y%m%d>*" path prefix suffix
    [[ "$path" == "/logs" ]]
    [[ "$prefix" == "app_<date:%Y%m%d>*" ]]
    [[ "$suffix" == "" ]]
}

@test "string_handler: date token with complex format is preserved" {
    local path="" prefix="" suffix=""
    string_handler "/logs::app_<date:%Y%m%d-%H%M%S>*" path prefix suffix
    [[ "$path" == "/logs" ]]
    [[ "$prefix" == "app_<date:%Y%m%d-%H%M%S>*" ]]
}

# --- multiple tokens combined ---

@test "string_handler: resolves env and keeps date token together" {
    local path="" prefix="" suffix=""
    string_handler "<env:HOME>/logs::app_<date:%Y%m%d>*" path prefix suffix
    [[ "$path" == "$HOME/logs" ]]
    [[ "$prefix" == "app_<date:%Y%m%d>*" ]]
    [[ "$suffix" == "" ]]
}

@test "string_handler: resolves env, keeps date, and extracts suffix" {
    local path="" prefix="" suffix=""
    string_handler "<env:HOME>/data::file_<date:%Y%m%d>*<suffix:.log>" path prefix suffix
    [[ "$path" == "$HOME/data" ]]
    [[ "$prefix" == "file_<date:%Y%m%d>*" ]]
    [[ "$suffix" == ".log" ]]
}

@test "string_handler: multiple env and cmd tokens resolved" {
    local path="" prefix="" suffix=""
    local expected_hostname
    expected_hostname="$(hostname)"
    string_handler "<env:HOME>/log_core::corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*" path prefix suffix
    [[ "$path" == "$HOME/log_core" ]]
    [[ "$prefix" == "corenavi_auto.${expected_hostname}.${USER}.log.INFO.<date:%Y%m%d-%H%M%S>*" ]]
    [[ "$suffix" == "" ]]
}

# --- path::file format ---

@test "string_handler: splits path and prefix on double colon" {
    local path="" prefix="" suffix=""
    string_handler "/var/log/app::server.log" path prefix suffix
    [[ "$path" == "/var/log/app" ]]
    [[ "$prefix" == "server.log" ]]
    [[ "$suffix" == "" ]]
}

# --- no special tokens ---

@test "string_handler: plain string with no tokens splits correctly" {
    local path="" prefix="" suffix=""
    string_handler "/home/user/logs::output.txt" path prefix suffix
    [[ "$path" == "/home/user/logs" ]]
    [[ "$prefix" == "output.txt" ]]
    [[ "$suffix" == "" ]]
}

@test "string_handler: plain string with wildcard prefix" {
    local path="" prefix="" suffix=""
    string_handler "/home/user/logs::*" path prefix suffix
    [[ "$path" == "/home/user/logs" ]]
    [[ "$prefix" == "*" ]]
    [[ "$suffix" == "" ]]
}

# --- complex real-world path ---

@test "string_handler: complex real-world lidar detection path" {
    local path="" prefix="" suffix=""
    string_handler '<env:HOME>/ros-docker/AMR/myuser/log_data/lidar_detection::detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*<suffix:.dat>' path prefix suffix
    [[ "$path" == "$HOME/ros-docker/AMR/myuser/log_data/lidar_detection" ]]
    [[ "$prefix" == "detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*" ]]
    [[ "$suffix" == ".dat" ]]
}

@test "string_handler: complex real-world slam log path" {
    local path="" prefix="" suffix=""
    string_handler '<env:HOME>/ros-docker/AMR/myuser/log_slam::coreslam_2D_<date:%s>*<suffix:.log>' path prefix suffix
    [[ "$path" == "$HOME/ros-docker/AMR/myuser/log_slam" ]]
    [[ "$prefix" == "coreslam_2D_<date:%s>*" ]]
    [[ "$suffix" == ".log" ]]
}

@test "string_handler: complex real-world glog path with no suffix" {
    local path="" prefix="" suffix=""
    string_handler '<env:HOME>/ros-docker/AMR/myuser/log_data/lidar_detection/glog::detect_shelf_node-DetectShelf-<date:%Y%m%d-%H%M%S>*' path prefix suffix
    [[ "$path" == "$HOME/ros-docker/AMR/myuser/log_data/lidar_detection/glog" ]]
    [[ "$prefix" == "detect_shelf_node-DetectShelf-<date:%Y%m%d-%H%M%S>*" ]]
    [[ "$suffix" == "" ]]
}

@test "string_handler: config file with no date or suffix tokens" {
    local path="" prefix="" suffix=""
    string_handler '<env:HOME>/ros-docker/AMR/myuser/core_storage::node_config.yaml' path prefix suffix
    [[ "$path" == "$HOME/ros-docker/AMR/myuser/core_storage" ]]
    [[ "$prefix" == "node_config.yaml" ]]
    [[ "$suffix" == "" ]]
}
