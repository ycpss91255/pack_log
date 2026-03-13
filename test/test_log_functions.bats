#!/usr/bin/env bats

setup() {
    load 'test_helper'
}

# --- log_verbose ---

@test "log_verbose: suppressed when VERBOSE < 2" {
    VERBOSE=0
    run log_verbose "test message"
    assert_success
    assert_output ""
}

@test "log_verbose: suppressed when VERBOSE is 1" {
    VERBOSE=1
    run log_verbose "test message"
    assert_success
    assert_output ""
}

@test "log_verbose: prints when VERBOSE >= 2" {
    VERBOSE=2
    run log_verbose "test message"
    assert_success
    # output goes to stderr, run captures both
    assert_output "test message"
}

@test "log_verbose: prints when VERBOSE is 3" {
    VERBOSE=3
    run log_verbose "test message"
    assert_success
    assert_output "test message"
}

# --- log_debug ---

@test "log_debug: suppressed when VERBOSE is 0" {
    VERBOSE=0
    run log_debug "debug msg"
    assert_success
    assert_output ""
}

@test "log_debug: prints when VERBOSE is 1" {
    VERBOSE=1
    run log_debug "debug msg"
    assert_success
    assert_output "DEBUG: debug msg"
}

@test "log_debug: prints when VERBOSE >= 2" {
    VERBOSE=2
    run log_debug "debug msg"
    assert_success
    assert_output "DEBUG: debug msg"
}

# --- log_info ---

@test "log_info: prints message to stdout" {
    run log_info "info message"
    assert_success
    assert_output "Info: info message"
}

# --- log_warn ---

@test "log_warn: prints message to stderr" {
    run log_warn "warning message"
    assert_success
    assert_output "Warn: warning message"
}

# --- log_error ---

@test "log_error: prints message and exits with 1" {
    run log_error "error message"
    assert_failure 1
    assert_output "Error: error message"
}

# --- print_help ---

@test "print_help: shows usage information" {
    run print_help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "--number"
    assert_output --partial "--start"
    assert_output --partial "--end"
    assert_output --partial "--help"
    assert_output --partial "--userhost"
    assert_output --partial "--local"
    assert_output --partial "--output"
    assert_output --partial "--verbose"
    assert_output --partial "--very-verbose"
    assert_output --partial "--extra-verbose"
}
