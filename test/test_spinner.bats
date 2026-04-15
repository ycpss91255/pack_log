#!/usr/bin/env bats

setup() {
    load 'test_helper'
    _SPINNER_PID=""
}

teardown() {
    # Ensure spinner is cleaned up after each test
    if [[ -n "${_SPINNER_PID}" ]]; then
        kill "${_SPINNER_PID}" 2>/dev/null || true
        wait "${_SPINNER_PID}" 2>/dev/null || true
        _SPINNER_PID=""
    fi
}

# --- spinner_start ---

@test "spinner_start: sets _SPINNER_PID when stderr is a terminal" {
    # Simulate terminal by overriding the tty check inside spinner_start.
    # In test environment, stderr is not a real terminal, so we override
    # _spinner_is_tty to return true.
    _spinner_is_tty() { return 0; }

    spinner_start "test message"

    [[ -n "${_SPINNER_PID}" ]]
    # Verify the process is actually running
    kill -0 "${_SPINNER_PID}" 2>/dev/null

    spinner_stop
}

@test "spinner_start: does not start when stderr is not a terminal" {
    _spinner_is_tty() { return 1; }

    spinner_start "test message"
    [[ -z "${_SPINNER_PID}" ]]
}

@test "spinner_start: stops previous spinner before starting new one" {
    _spinner_is_tty() { return 0; }

    spinner_start "first message"
    local first_pid="${_SPINNER_PID}"
    [[ -n "${first_pid}" ]]

    spinner_start "second message"
    local second_pid="${_SPINNER_PID}"
    [[ -n "${second_pid}" ]]

    # First process should be gone
    ! kill -0 "${first_pid}" 2>/dev/null
    # Second process should be running
    kill -0 "${second_pid}" 2>/dev/null

    spinner_stop
}

# --- spinner_stop ---

@test "spinner_stop: kills the spinner process" {
    _spinner_is_tty() { return 0; }

    spinner_start "test message"
    local pid="${_SPINNER_PID}"
    [[ -n "${pid}" ]]

    spinner_stop

    [[ -z "${_SPINNER_PID}" ]]
    ! kill -0 "${pid}" 2>/dev/null
}

@test "spinner_stop: safe to call when no spinner is running" {
    _SPINNER_PID=""
    run spinner_stop
    assert_success
}

@test "spinner_stop: safe to call multiple times" {
    _spinner_is_tty() { return 0; }

    spinner_start "test message"
    spinner_stop
    run spinner_stop
    assert_success
    [[ -z "${_SPINNER_PID}" ]]
}

# --- i18n messages ---

@test "MSG_SPINNER_*: all spinner messages defined for en" {
    LANG_CODE="en"; load_lang
    [[ -n "${MSG_SPINNER_SSH}" ]]
    [[ -n "${MSG_SPINNER_TOKEN}" ]]
    [[ -n "${MSG_SPINNER_FINDING}" ]]
    [[ -n "${MSG_SPINNER_COPYING}" ]]
    [[ -n "${MSG_SPINNER_SIZE}" ]]
    [[ -n "${MSG_SPINNER_ARCHIVE}" ]]
}

@test "MSG_SPINNER_*: all spinner messages defined for zh-TW" {
    LANG_CODE="zh-TW"; load_lang
    [[ -n "${MSG_SPINNER_SSH}" ]]
    [[ -n "${MSG_SPINNER_TOKEN}" ]]
    [[ -n "${MSG_SPINNER_FINDING}" ]]
    [[ -n "${MSG_SPINNER_COPYING}" ]]
    [[ -n "${MSG_SPINNER_SIZE}" ]]
    [[ -n "${MSG_SPINNER_ARCHIVE}" ]]
}

@test "MSG_SPINNER_*: all spinner messages defined for zh-CN" {
    LANG_CODE="zh-CN"; load_lang
    [[ -n "${MSG_SPINNER_SSH}" ]]
    [[ -n "${MSG_SPINNER_TOKEN}" ]]
    [[ -n "${MSG_SPINNER_FINDING}" ]]
    [[ -n "${MSG_SPINNER_COPYING}" ]]
    [[ -n "${MSG_SPINNER_SIZE}" ]]
    [[ -n "${MSG_SPINNER_ARCHIVE}" ]]
}

@test "MSG_SPINNER_*: all spinner messages defined for ja" {
    LANG_CODE="ja"; load_lang
    [[ -n "${MSG_SPINNER_SSH}" ]]
    [[ -n "${MSG_SPINNER_TOKEN}" ]]
    [[ -n "${MSG_SPINNER_FINDING}" ]]
    [[ -n "${MSG_SPINNER_COPYING}" ]]
    [[ -n "${MSG_SPINNER_SIZE}" ]]
    [[ -n "${MSG_SPINNER_ARCHIVE}" ]]
}
