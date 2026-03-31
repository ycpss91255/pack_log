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
    assert_output "[DEBUG] debug msg"
}

@test "log_debug: prints when VERBOSE >= 2" {
    VERBOSE=2
    run log_debug "debug msg"
    assert_success
    assert_output "[DEBUG] debug msg"
}

# --- log_info ---

@test "log_info: prints message to stdout" {
    run log_info "info message"
    assert_success
    assert_output "[INFO]  info message"
}

# --- log_warn ---

@test "log_warn: prints message to stderr" {
    run log_warn "warning message"
    assert_success
    assert_output "[WARN]  warning message"
}

# --- log_error ---

@test "log_error: prints message and exits with 1" {
    run log_error "error message"
    assert_failure 1
    assert_output "[ERROR] error message"
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
    assert_output --partial "--lang"
}

# --- _log_to_file ---

@test "_log_to_file: no-op when _LOG_FD is empty" {
    _LOG_FD=""
    run _log_to_file "test message"
    assert_success
    assert_output ""
}

@test "_log_to_file: writes to fd when initialized" {
    local tmpfile="${BATS_TEST_TMPDIR}/test_log.log"
    exec {_LOG_FD}>>"${tmpfile}"
    _log_to_file "hello log file"
    exec {_LOG_FD}>&-
    _LOG_FD=""
    assert_file_exists "${tmpfile}"
    run cat "${tmpfile}"
    assert_output "hello log file"
}

# --- init_log_file / close_log_file ---

@test "init_log_file: creates pack_log.log in SAVE_FOLDER" {
    local tmpdir="${BATS_TEST_TMPDIR}/test_save"
    mkdir -p "${tmpdir}"
    SAVE_FOLDER="${tmpdir}"
    init_log_file
    assert_file_exists "${tmpdir}/pack_log.log"
    [[ -n "${_LOG_FD}" ]]
    close_log_file
    [[ -z "${_LOG_FD}" ]]
}

@test "log functions write to log file without ANSI codes" {
    local tmpdir="${BATS_TEST_TMPDIR}/test_log_output"
    mkdir -p "${tmpdir}"
    SAVE_FOLDER="${tmpdir}"
    init_log_file
    log_info "info test"
    log_warn "warn test"
    VERBOSE=2
    log_debug "debug test"
    log_verbose "verbose test"
    close_log_file
    run cat "${tmpdir}/pack_log.log"
    assert_output --partial "[INFO]  info test"
    assert_output --partial "[WARN]  warn test"
    assert_output --partial "[DEBUG] debug test"
    assert_output --partial "[VERBOSE] verbose test"
    # Verify no ANSI escape codes
    refute_output --partial $'\033['
}

@test "close_log_file: safe to call multiple times" {
    _LOG_FD=""
    close_log_file
    close_log_file
}

# --- i18n / load_lang ---

@test "load_lang: loads English by default" {
    LANG_CODE="en"
    load_lang
    [[ "${MSG_SUCCESS}" == "Packaging log completed successfully." ]]
}

@test "load_lang: loads zh-TW messages" {
    LANG_CODE="zh-TW"
    load_lang
    [[ "${MSG_SUCCESS}" == "打包 log 完成。" ]]
    # Restore
    LANG_CODE="en"
    load_lang
}

@test "load_lang: loads ja messages" {
    LANG_CODE="ja"
    load_lang
    [[ "${MSG_STEP1}" == "=== ステップ 1/5: ターゲットホストの解決 ===" ]]
    # Restore
    LANG_CODE="en"
    load_lang
}

@test "load_lang: MSG_RESOLVED_PATH is translated for zh-TW" {
    LANG_CODE="zh-TW"
    load_lang
    [[ "${MSG_RESOLVED_PATH}" == *"解析結果"* ]]
    # Restore
    LANG_CODE="en"
    load_lang
}

@test "load_lang: MSG_RESOLVED_PATH is translated for zh-CN" {
    LANG_CODE="zh-CN"
    load_lang
    [[ "${MSG_RESOLVED_PATH}" == *"解析结果"* ]]
    # Restore
    LANG_CODE="en"
    load_lang
}

@test "load_lang: MSG_RESOLVED_PATH is translated for ja" {
    LANG_CODE="ja"
    load_lang
    [[ "${MSG_RESOLVED_PATH}" == *"解決済み"* ]]
    # Restore
    LANG_CODE="en"
    load_lang
}

@test "load_lang: falls back to English for unknown language" {
    LANG_CODE="xx-UNKNOWN"
    load_lang
    [[ "${MSG_SUCCESS}" == "Packaging log completed successfully." ]]
}

# --- i18n completeness: all MSGs defined and format args consistent ---

@test "load_lang: all languages define the same MSG variables" {
    # Collect MSG names from English
    LANG_CODE="en"
    load_lang
    local -a en_msgs=()
    local var
    for var in $(compgen -v MSG_); do
        en_msgs+=("${var}")
    done

    # Check each language has the same set
    for lang in zh-TW zh-CN ja; do
        LANG_CODE="${lang}"
        load_lang
        for var in "${en_msgs[@]}"; do
            [[ -n "${!var+set}" ]] || { echo "MISSING: ${var} in ${lang}"; return 1; }
        done
    done

    # Restore
    LANG_CODE="en"
    load_lang
}

@test "load_lang: format arg counts match across all languages" {
    # Get English format arg counts
    LANG_CODE="en"
    load_lang
    local -A en_fmt_counts=()
    local var val count
    for var in $(compgen -v MSG_); do
        val="${!var}"
        count=$(echo "${val}" | grep -oP '%[sd]' | wc -l)
        en_fmt_counts["${var}"]="${count}"
    done

    # Compare each language
    for lang in zh-TW zh-CN ja; do
        LANG_CODE="${lang}"
        load_lang
        for var in "${!en_fmt_counts[@]}"; do
            val="${!var}"
            count=$(echo "${val}" | grep -oP '%[sd]' | wc -l)
            if [[ "${count}" -ne "${en_fmt_counts["${var}"]}" ]]; then
                echo "MISMATCH: ${var} in ${lang}: expected ${en_fmt_counts["${var}"]} format args, got ${count}"
                return 1
            fi
        done
    done

    # Restore
    LANG_CODE="en"
    load_lang
}
