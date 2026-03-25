#!/bin/bash
#
# pack_log.sh — Log collection tool for robotic fleet deployments.
#
# Connects to remote hosts via SSH, finds log files within a specified time
# range using a token-based path system, copies them to a temporary folder,
# and transfers them back locally via rsync/scp/sftp. Also supports local
# mode (no SSH).
#
# Usage:
#   ./pack_log.sh -n 1 -s 20260101-000000 -e 20260101-235959
#   ./pack_log.sh -u myuser@10.90.68.188 -s 20260101-000000 -e 20260101-235959
#   ./pack_log.sh -l -s 20260101-000000 -e 20260101-235959
#
# For more information, run the script with the --help option.
#
# Author: Yunchien.chen <yunchien.chen@coretronic-robotics.com>
# Date: 2026-03-13
# Version: 1.4.0

set -euo pipefail

# ==============================================================================
# User Configuration (frequently adjusted per deployment site)
# ==============================================================================

# KCOV_EXCL_START
declare -a HOSTS=(
  # # lixing
  # "core-03::myuser@192.168.11.161"
  # "kimb-01::myuser@192.168.11.166"

  # # guotai
  # "circ2::myuser@192.168.11.114"

  # Panasonic AMR
  "pana01::myuser@10.90.68.188"
  "pana02::myuser@10.90.68.191"
  "pana03::myuser@10.90.68.15"
  "pana04::myuser@10.90.68.14"
  "pana05::myuser@10.90.69.16"
  "pana06::myuser@10.90.69.17"
  "pana07::myuser@10.90.69.101"

  # # ASE Us
  # "mr1202::myuser@10.11.236.54"
  # "mr1203::myuser@10.11.199.79"
  # "mr1204::myuser@10.11.199.252"
  # "mr1205::myuser@10.11.199.253"
  # "mr1206::myuser@10.11.199.9"
  # "t2003::myuser@10.11.199.11"
)
# KCOV_EXCL_STOP

# Log paths format:
# <path>::<file>
#
# To get all files in a folder, just use the folder path without any special
# format, for example:
#   "/home/user/logs::*"
#
# Special formats are also supported:
#
# 1. Use an environment variable: <env:VAR_NAME>
#    e.g. "<env:HOME>/logs"
#
# 2. Use a shell command: <cmd:your_command>
#    e.g. "<cmd:hostname>/logs"
#
# 3. Use a suffix to filter files: <suffix:yyy>
#    e.g. "logs::<suffix:yyy>"
#
# 4. Set a date format for time-range filtering: <date:format>
#    Supports any strftime format, e.g. %Y%m%d%H%M%S, %Y-%m-%d-%H-%M-%S, %s (epoch)
#    e.g. "logs::<date:%Y%m%d>" or "logs::<date:%Y%m%d-%H%M%S>"
# KCOV_EXCL_START
declare -a LOG_PATHS=(
  # Panasonic
  # LiDAR Detection shelf log path (docker)
  '<env:HOME>/ros-docker/AMR/myuser/log_core::corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*'
  '<env:HOME>/ros-docker/AMR/myuser/log_data/lidar_detection::detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*<suffix:.dat>'
  '<env:HOME>/ros-docker/AMR/myuser/log_data/lidar_detection::detect_shelf_<date:%Y%m%d%H%M%S>*<suffix:.pcd>'
  '<env:HOME>/ros-docker/AMR/myuser/log_data/lidar_detection/glog::detect_shelf_node-DetectShelf-<date:%Y%m%d-%H%M%S>*'
  '<env:HOME>/ros-docker/AMR/myuser/log_slam::coreslam_2D_<date:%s>*<suffix:.log>'
  '<env:HOME>/ros-docker/AMR/myuser/log_slam/record::coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*<suffix:.rec>'
  '<env:HOME>/ros-docker/AMR/myuser/core_storage::node_config.yaml'
  '<env:HOME>/ros-docker/AMR/myuser/core_storage::shelf.ini'
  '<env:HOME>/ros-docker/AMR/myuser/core_storage::external_param.launch'
  '<env:HOME>/ros-docker/AMR/myuser/core_storage::run_config.yaml'

  # # ASE Us
  # # LiDAR Detection pallet log path
  # '<env:HOME>/log_data/lidar_detection::detect_pallet_node-DetectPallet_<date:%Y%m%d%H%M%S>*<suffix:.dat>'
  # '<env:HOME>/log_data/lidar_detection::detect_pallet_node-DetectPallet_<date:%Y%m%d%H%M%S>*<suffix:.pcd>'
  # '<env:HOME>/log_data/lidar_detection/glog::detect_pallet_node-DetectPallet-<date:%Y%m%d-%H%M%S>*'
  # '<env:HOME>/coretronic_amr_navi_install/share/lidar_detection_pkg/config::pallet.ini'
)
# KCOV_EXCL_STOP

declare SAVE_FOLDER="log_pack"

# ==============================================================================
# Tunable Parameters (occasionally adjusted)
# ==============================================================================

declare SSH_KEY="${HOME}/.ssh/get_log"
declare SSH_TIMEOUT=3
declare TRANSFER_MAX_RETRIES=3
declare TRANSFER_RETRY_DELAY=5

# ==============================================================================
# Internal Variables (do not modify)
# ==============================================================================

declare -r VERSION="1.4.0"
declare VERBOSE=0
declare NUM="" HOST="" GET_LOG_TOOL=""
declare START_TIME="" END_TIME=""
declare LANG_CODE=""
declare LOG_FILE="" _LOG_FD=""

# KCOV_EXCL_START
declare -a SSH_OPTS=(
    -i "${SSH_KEY}"
    -o BatchMode=yes
    -o ConnectTimeout="${SSH_TIMEOUT}"
    -o NumberOfPasswordPrompts=0
    -o PreferredAuthentications=publickey
    # WARNING: StrictHostKeyChecking=no disables host key verification.
    # This is acceptable for trusted internal networks but poses MITM risks.
    -o StrictHostKeyChecking=no
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=3
  )
# KCOV_EXCL_STOP

unset HAVE_SUDO_ACCESS

# Cache for resolved remote token values (avoids repeated SSH calls)
declare -gA _TOKEN_CACHE=()

# --- i18n ---
# Loads the language file based on LANG_CODE.
load_lang() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local lang_file="${script_dir}/doc/lang/${LANG_CODE}.sh"

  if [[ ! -f "${lang_file}" ]]; then
    lang_file="${script_dir}/doc/lang/en.sh"
  fi
  # shellcheck source=/dev/null
  source "${lang_file}"
}

# Load default language on source (can be overridden by --lang or $LANG in main)
LANG_CODE="en"
load_lang

# --- Log functions ---
# Color codes (disabled when stdout/stderr is not a terminal)
# KCOV_EXCL_START — terminal color detection depends on runtime tty
if [[ -t 2 ]]; then
  _C_RESET='\033[0m'
  _C_RED='\033[1;31m'
  _C_YELLOW='\033[1;33m'
  _C_GREEN='\033[0;32m'
  _C_CYAN='\033[0;36m'
  _C_DIM='\033[2m'
# KCOV_EXCL_STOP
else
  _C_RESET='' _C_RED='' _C_YELLOW='' _C_GREEN='' _C_CYAN='' _C_DIM=''
fi

# Writes plain-text log entry to the log file (no-op if log file not yet initialized)
_log_to_file() {
  [[ -n "${_LOG_FD}" ]] && printf '%s\n' "$*" >&"${_LOG_FD}"
  return 0
}

# Opens the log file for writing. Call after SAVE_FOLDER is finalized.
init_log_file() {
  LOG_FILE="${SAVE_FOLDER}/pack_log.log"
  exec {_LOG_FD}>>"${LOG_FILE}"
}

# Closes the log file descriptor. Safe to call multiple times.
close_log_file() {
  if [[ -n "${_LOG_FD}" ]]; then
    exec {_LOG_FD}>&-
    _LOG_FD=""
  fi
}

log_verbose() { [[ "${VERBOSE:-0}" -ge 2 ]] && printf "${_C_DIM}%s${_C_RESET}\n" "$*" >&2; _log_to_file "[VERBOSE] $*"; return 0; }
log_debug()   { [[ "${VERBOSE:-0}" -ge 1 ]] && printf "${_C_CYAN}[DEBUG]${_C_RESET} %s\n" "$*" >&2; _log_to_file "[DEBUG] $*"; return 0; }
log_info()    { printf "${_C_GREEN}[INFO]${_C_RESET}  %s\n" "$*"; _log_to_file "[INFO]  $*"; }
log_warn()    { printf "${_C_YELLOW}[WARN]${_C_RESET}  %s\n" "$*" >&2; _log_to_file "[WARN]  $*"; }
log_error()   { printf "${_C_RED}[ERROR]${_C_RESET} %s\n" "$*" >&2; _log_to_file "[ERROR] $*"; close_log_file; exit 1; }

# Prints the help message for the script.
print_help() {
  # shellcheck disable=SC2059
  printf "${MSG_HELP_USAGE}\n" "$(basename "$0")"
  echo "${MSG_HELP_OPTIONS}"
  # shellcheck disable=SC2059
  printf "${MSG_HELP_NUMBER}\n" "${#HOSTS[@]}"
  echo "${MSG_HELP_USERHOST}"
  echo "${MSG_HELP_LOCAL}"
  echo "${MSG_HELP_START}"
  echo "${MSG_HELP_END}"
  echo "${MSG_HELP_OUTPUT}"
  echo "${MSG_HELP_LANG}"
  echo "${MSG_HELP_VERBOSE}"
  echo "${MSG_HELP_VERY_VERBOSE}"
  echo "${MSG_HELP_EXTRA_VERBOSE}"
  echo "${MSG_HELP_HELP}"
  echo "${MSG_HELP_VERSION}"
}

# Support functions

# Checks if the user has sudo access.
#
# This function checks if the user has sudo access by running `sudo -v` and
# `sudo -l`. It caches the result in the `HAVE_SUDO_ACCESS` variable to avoid
# checking multiple times.
#
# Returns:
#   0 if the user has sudo access or is root.
#   1 otherwise.
have_sudo_access() {
  local -a sudo_cmd=("/usr/bin/sudo")

  # check if already root
  if [[ "${EUID:-${UID}}" -eq 0 ]]; then
    return 0
  fi

  # KCOV_EXCL_START — kcov cannot instrument these bash conditionals
  # check sudo executable exists and is executable
  if [[ ! -x "/usr/bin/sudo" ]]; then
    return 1
  fi

  # processing SUDO_ASKPASS
  if [[ -n "${SUDO_ASKPASS-}" ]]; then
    sudo_cmd+=("-A")
  fi

  # check sudo access only once
  if [[ -z "${HAVE_SUDO_ACCESS-}" ]]; then
    log_info "${MSG_CHECKING_SUDO}"
    "${sudo_cmd[@]}" -v && "${sudo_cmd[@]}" -l mkdir &>/dev/null
    HAVE_SUDO_ACCESS="$?"
  fi
  # KCOV_EXCL_STOP

  return "${HAVE_SUDO_ACCESS}" # KCOV_EXCL_LINE
}

# Installs a package using apt-get if it is not already installed.
#
# Arguments:
#   pkg_name: The name of the package to install.
pkg_install_handler() {
  local -r pkg_name="$1"

  log_verbose "${FUNCNAME[0]} input is: "
  log_verbose "  pkg_name: ${pkg_name}"

  # Check if the package is already installed.
  if command -v "${pkg_name}" >/dev/null 2>&1; then
    log_debug "$(printf "${MSG_PKG_ALREADY_INSTALLED}" "${pkg_name}")"
    return 0
  fi

  log_info "$(printf "${MSG_PKG_NOT_FOUND}" "${pkg_name}")"

  # Check for sudo access. If missing, return error immediately.
  if ! have_sudo_access; then
    log_error "$(printf "${MSG_NO_SUDO_ACCESS}" "${pkg_name}")" # KCOV_EXCL_LINE
  fi

  # Attempt to update and install the package.
  # We separate the logic to ensure 'return 1' only runs on failure.
  if ! { sudo apt-get update && sudo apt-get install -y "${pkg_name}"; }; then
    log_warn "$(printf "${MSG_PKG_INSTALL_FAILED}" "${pkg_name}")"
    return 0
  fi

  log_verbose "--------------------" # KCOV_EXCL_LINE
}

# Converts a date string (YYYYmmdd-HHMMSS) to the given strftime format.
#
# Arguments:
#   date:   The date string in YYYYmmdd-HHMMSS format.
#   format: The strftime format to convert to (e.g. %Y%m%d%H%M%S, %s).
#
# Sets:
#   REPLY: The formatted date string.
date_format() {
  local -r date="${1:?"${FUNCNAME[0]} need date."}"; shift
  local -r format="${1:?"${FUNCNAME[0]} need format."}"; shift

  log_verbose "${FUNCNAME[0]} input is: "
  log_verbose "  date: ${date}"
  log_verbose "  format: ${format}"

  if [[ ! "${date}" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
    log_error "$(printf "${MSG_INVALID_DATE_FORMAT}" "${date}")"
  fi

  local ymd hms
  ymd="${date:0:4}-${date:4:2}-${date:6:2}"
  hms="${date:9:2}:${date:11:2}:${date:13:2}"

  if ! REPLY=$(date -d "${ymd} ${hms}" "+${format}"); then
    log_error "$(printf "${MSG_DATE_FORMAT_FAILED}" "${date}")" # KCOV_EXCL_LINE
  fi

  log_verbose "${FUNCNAME[0]} output: ${REPLY}"
  log_verbose "--------------------"
}

# Executes a shell command locally or on a remote host via SSH.
#
# Pipes the command string into 'bash -ls' via stdin, bypassing complex
# shell escaping and nested quoting issues.
#
# Arguments:
#   inner_cmd: The shell command string to execute.
execute_cmd() {
  local -r inner_cmd="${1:?"${FUNCNAME[0]} need inner command."}"; shift
  local ret=0

  log_verbose "${FUNCNAME[0]} input is: "
  log_verbose "  inner_cmd: ${inner_cmd}"
  log_verbose "  HOST: ${HOST}"
  log_verbose "  SSH_KEY: ${SSH_KEY}"
  log_verbose "  SSH_TIMEOUT: ${SSH_TIMEOUT}"

  if [[ "${HOST}" == "local" ]]; then
    printf '%s' "${inner_cmd}" | bash -ls
    ret=$?
  else
    printf '%s' "${inner_cmd}" | ssh "${SSH_OPTS[@]}" "${HOST}" bash -ls
    ret=$?
  fi
  log_verbose "--------------------"
  return "${ret}"
}

# Resolves a remote token value (environment variable or command output).
#
# Results are cached in _TOKEN_CACHE to avoid redundant SSH calls when
# the same token (e.g. <env:HOME>) appears in multiple LOG_PATHS entries.
#
# Arguments:
#   type: Token type — "env" (environment variable) or "cmd" (shell command).
#   str:  The variable name or command to resolve.
#
# Sets:
#   REPLY: The resolved value.
get_remote_value() {
  local -r type="${1:?"${FUNCNAME[0]} need type."}"; shift
  local -r str="${1:?"${FUNCNAME[0]} need string."}"; shift

  log_verbose "${FUNCNAME[0]} input is: "
  log_verbose "  type: ${type}"
  log_verbose "  str: ${str}"
  log_verbose "  HOST: ${HOST}"

  # Check cache first to avoid redundant SSH calls
  local cache_key="${type}:${str}"
  if [[ -n "${_TOKEN_CACHE["${cache_key}"]+set}" ]]; then
    REPLY="${_TOKEN_CACHE["${cache_key}"]}"
    log_debug "Cache hit: ${cache_key} = ${REPLY}"
    return 0
  fi

  if [[ "${HOST}" == "local" && "${type}" == "env" ]]; then
    REPLY="${!str}"
    _TOKEN_CACHE["${cache_key}"]="${REPLY}"
    return 0
  fi

  local get_cmd=""
  if [[ "${type}" == "env" ]]; then
    printf -v get_cmd 'printf "%%s" "${%s}"' "${str}" # KCOV_EXCL_LINE
  elif [[ "${type}" == "cmd" ]]; then
    get_cmd="${str}"
  else
    log_error "$(printf "${MSG_UNKNOWN_TOKEN_TYPE}" "${type}")"
  fi

  log_debug "Executing command: ${get_cmd}"

  if ! REPLY=$(execute_cmd "${get_cmd}"); then
    log_error "$(printf "${MSG_COMMAND_FAILED}" "${get_cmd}")" # KCOV_EXCL_LINE
  fi
  _TOKEN_CACHE["${cache_key}"]="${REPLY}"

  log_verbose "--------------------"
}

# Creates a folder on the local or remote machine.
#
# Arguments:
#   path: The path of the folder to create.
create_folder() {
  local -r path="${1:?"${FUNCNAME[0]} need path."}"; shift

  log_verbose "${FUNCNAME[0]} input is: "
  log_verbose "  path: ${path}"
  log_verbose "  HOST: ${HOST}"

  local mkdir_cmd
  printf -v mkdir_cmd "mkdir -p %q" "${path}"
  readonly mkdir_cmd

  if ! execute_cmd "${mkdir_cmd}"; then
    log_error "$(printf "${MSG_FOLDER_CREATE_FAILED}" "${path}")" # KCOV_EXCL_LINE
  fi

  log_verbose "--------------------"
}

# Executes a command using an array of strings as null-delimited stdin.
#
# Arguments:
#   inner_cmd: The command to execute (e.g., "xargs ...").
#   ...:       Array elements to pipe as null-delimited stdin.
execute_cmd_from_array() {
  local -r inner_cmd="${1:?"${FUNCNAME[0]} need inner command."}"; shift
  local ret=0

  log_verbose "${FUNCNAME[0]} input is: "
  log_verbose "  inner_cmd: ${inner_cmd}"
  log_verbose "  array size: $# elements"
  log_verbose "  HOST: ${HOST}"

  if [[ "${HOST}" == "local" ]]; then
    # Directly pipe formatted array to eval
    printf "%s\0" "$@" | eval "${inner_cmd}"
    ret=$?
  else
    # Pipe formatted array directly through SSH
    printf "%s\0" "$@" | ssh "${SSH_OPTS[@]}" "${HOST}" "${inner_cmd}"
    ret=$?
  fi

  log_verbose "--------------------"
  return "${ret}"
}

# Main functions

# Parses the command-line options.
#
# This function uses `getopt` to parse the command-line options and set the
# corresponding variables.
#
# Arguments:
#   $@: The command-line options.
option_parser() {
  # KCOV_EXCL_START
  local -a short_opts_arr=(
    "n:" "u:" "l"
    "s:" "e:"
    "o:"
    "v" "h"
  )

  local -a long_opts_arr=(
    "number:" "userhost:" "local"
    "start:"  "end:"
    "output:"
    "verbose" "very-verbose" "extra-verbose"
    "lang:"
    "help" "version"
  )
  # KCOV_EXCL_STOP

  local short_opts long_opts
  short_opts=$(printf "%s" "${short_opts_arr[@]}")
  long_opts=$(IFS=,; echo "${long_opts_arr[@]}")

  local parsed
  if ! parsed=$(getopt -o "${short_opts}" --long "${long_opts}" -n "${FUNCNAME[0]}" -- "$@"); then
    print_help; exit 1
  fi

  eval set -- "${parsed}"

  while true; do
    case "$1" in
      -n | --number)
        NUM="$2"; shift 2 ;;
      -u | --userhost)
        HOST="$2"; shift 2 ;;
      -l | --local)
        HOST="local"; shift ;;
      -s | --start)
        START_TIME="$2"; shift 2 ;;
      -e | --end)
        END_TIME="$2"; shift 2 ;;
      -o | --output)
        SAVE_FOLDER="$2"; shift 2 ;;
      -v | --verbose)
        VERBOSE=$((VERBOSE + 1)); shift ;;
      --very-verbose)
        VERBOSE=2; shift ;;
      --extra-verbose)
        VERBOSE=3; shift ;; # KCOV_EXCL_LINE
      --lang)
        LANG_CODE="$2"; shift 2 ;;
      -h | --help)
        # Resolve language before printing help
        if [[ -z "${LANG_CODE}" ]]; then
          case "${LANG:-}" in
            zh_TW*) LANG_CODE="zh-TW" ;; zh_CN*|zh_SG*) LANG_CODE="zh-CN" ;;
            ja*) LANG_CODE="ja" ;; *) LANG_CODE="en" ;;
          esac
        fi
        load_lang; print_help; exit 0 ;;
      --version)
        printf "%s\n" "${VERSION}"; exit 0 ;;
      --) shift; break ;;
      *) break ;; # KCOV_EXCL_LINE
    esac
  done

  if [[ "${VERBOSE:-0}" -ge 3 ]]; then
    set -x # KCOV_EXCL_LINE
  fi
}

# Handles the host selection.
#
# This function determines which host to connect to based on the user's input.
# It can be a number from the `HOSTS` array, a `user@host` string, or "local".
# If no host is provided, it prompts the user to select one.
host_handler() {
  log_verbose "${FUNCNAME[0]} input is: "
  log_verbose "  NUM: ${NUM}"
  log_verbose "  HOST: ${HOST}"

  if [[ "${HOST}" == "local" ]]; then
    log_debug "${MSG_HOST_USING_LOCAL}"
    return 0
  fi

  # find max length of host names for formatting
  local num_width=${#HOSTS[@]}
  num_width=${#num_width}

  local max_len=0 item
  for item in "${HOSTS[@]}"; do
    local name="${item%%::*}"
    if (( ${#name} > max_len )); then
      max_len=${#name}
    fi
  done

  # check user input for number or user@host
  if [[ -z "${NUM}" && -z "${HOST}" ]]; then
    log_debug "No number or user@host provided, prompting for input"
    for i in "${!HOSTS[@]}"; do
      local name="${HOSTS[i]%%::*}"
      local userhost="${HOSTS[i]#*::}"
      printf "%*d. [%-*s] %s\n" "${num_width}" $(( i + 1 )) "${max_len}" "${name}" "${userhost}"
    done

    local input=""
    read -er -p "$(printf "${MSG_HOST_PROMPT}" "${#HOSTS[@]}")" input
    if [[ "${input,,}" == "local" ]]; then
      log_debug "${MSG_HOST_USING_LOCAL}"
      HOST="local"
      return 0
    elif [[ "${input}" =~ ^[1-9][0-9]*$ ]]; then
      log_debug "User selected number ${input}"
      NUM="${input}"
      HOST=""
    elif [[ "${input}" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]]; then
      log_debug "User provided user@host ${input}"
      HOST="${input}"
      NUM=""
    else
      log_error "$(printf "${MSG_INVALID_INPUT}" "${input}")" # KCOV_EXCL_LINE
    fi
  fi

  # check number
  if [[ "${NUM}" =~ ^[1-9][0-9]*$ ]]; then
    if (( "${NUM}" < 1 || "${NUM}" > ${#HOSTS[@]} )); then
      log_error "$(printf "${MSG_HOST_NUMBER_RANGE}" "${#HOSTS[@]}")"
    fi

    log_debug "Use number ${NUM} to get host"
    HOST="${HOSTS[${NUM}-1]#*::}"
  fi

  # check user@host format
  if [[ ! "${HOST}" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]]; then
    log_error "$(printf "${MSG_INVALID_USERHOST}" "${HOST}")"
  fi

  log_verbose "${FUNCNAME[0]} output is: "
  log_verbose "  HOST after: ${HOST}"
  log_verbose "--------------------"
}

# Handles the time range selection.
#
# This function prompts the user to enter the start and end times for the log
# search if they are not provided as command-line options. It validates the
# format of the input.
time_handler() {
  local t=""
  for t in START_TIME END_TIME; do
    local time=""

    if [[ -z "${!t}" ]]; then
      read -er -p "$(printf "${MSG_TIME_PROMPT}" "${t,,}")" time # KCOV_EXCL_LINE
    else
      time="${!t}"
    fi

    if [[ "${time}" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
      printf -v "${t}" "%s" "${time}"
    else
      log_error "$(printf "${MSG_INVALID_TIME_FORMAT}" "${t,,}" "${time}")"
    fi
  done

  # Validate start < end
  if [[ "${START_TIME}" > "${END_TIME}" ]]; then
    log_error "$(printf "${MSG_START_BEFORE_END}" "${START_TIME}" "${END_TIME}")"
  fi
}

# Handles the SSH connection.
#
# This function checks for the SSH key, creates it if it doesn't exist, and
# copies it to the remote host. It also handles known hosts and retries the
# connection if it fails.
ssh_handler() {
  # non-local machine, check and install ssh package
  pkg_install_handler "ssh" || exit 1

  local -r known_hosts="${HOME}/.ssh/known_hosts"
  local -r host_ip="${HOST#*@}"

  local -r max_retries=3
  local attempt=0
  local -a err_msgs=()
  local err_msg=""

  while (( attempt < max_retries )); do
    log_debug "$(printf "${MSG_SSH_ATTEMPT}" "${HOST}" "$(( attempt + 1 ))" "${max_retries}")"

    if err_msg=$(execute_cmd "true" 2>&1); then
        log_debug "$(printf "${MSG_SSH_SUCCESS}" "${HOST}")"
        return 0
    fi

    err_msgs+=( "attempt $(( attempt + 1 )): ${err_msg}" )

    local need_create_key="false" need_remove_host="false" need_copy_key="false"

    if [[ -f "${SSH_KEY}" ]]; then
      log_debug "$(printf "${MSG_SSH_KEY_EXISTS}" "${SSH_KEY}")"
      case "${err_msg}" in
        *"Permission denied"*)
          log_debug "${MSG_SSH_PERMISSION_DENIED}"
          need_copy_key="true"
          ;;
        *"Host key verification failed"*|*"REMOTE HOST IDENTIFICATION HAS CHANGED!"*)
          log_debug "${MSG_SSH_HOST_CHANGED}"
          need_remove_host="true"
          ;;
        *)
          log_error "$(printf "${MSG_SSH_FAILED}" "${err_msg}")"
          ;;
      esac
    else
      log_debug "$(printf "${MSG_SSH_KEY_NOT_FOUND}" "${SSH_KEY}")"
      need_create_key="true"
      need_copy_key="true"
    fi

    if [[ "${need_create_key}" == "true" ]]; then
      log_debug "${MSG_SSH_KEY_CREATING}"
      local dsa=""
      for dsa in ed25519 rsa; do
        [[ -f "${SSH_KEY}" ]] && break
        log_info "$(printf "${MSG_SSH_KEY_CREATE_WITH}" "${SSH_KEY}" "${dsa}")"
        ssh-keygen -t "${dsa}" -f "${SSH_KEY}" -N "" 2>/dev/null && break
      done
      [[ -f "${SSH_KEY}" ]] || log_error "$(printf "${MSG_SSH_KEY_CREATE_FAILED}" "${SSH_KEY}")"
    fi

    if [[ "${need_remove_host}" == "true" ]]; then
      if ssh-keygen -F "${host_ip}" &>/dev/null; then
        log_info "$(printf "${MSG_SSH_HOST_KEY_REMOVE}" "${host_ip}")"
        ssh-keygen -R "${host_ip}" &>/dev/null
      fi
      log_info "$(printf "${MSG_SSH_HOST_KEY_ADD}" "${host_ip}")"
      ssh-keyscan -H "${host_ip}" >> "${known_hosts}" 2>/dev/null
    fi

    if [[ "${need_copy_key}" == "true" ]]; then
      [[ -f "${SSH_KEY}" ]] || log_error "$(printf "${MSG_SSH_PRIVATE_NOT_FOUND}" "${SSH_KEY}")"
      [[ -f "${SSH_KEY}.pub" ]] || log_error "$(printf "${MSG_SSH_PUBLIC_NOT_FOUND}" "${SSH_KEY}.pub")"

      local derived_key
      derived_key=$(ssh-keygen -y -f "${SSH_KEY}" 2>/dev/null | awk '{print $1, $2}') \
        || log_error "$(printf "${MSG_SSH_KEY_INVALID}" "${SSH_KEY}")"

      local file_key
      file_key=$(awk '{print $1, $2}' "${SSH_KEY}.pub")
      [[ "${derived_key}" == "${file_key}" ]] || log_error "${MSG_SSH_KEY_MISMATCH}"

      ssh-copy-id -i "${SSH_KEY}.pub" \
        -o ConnectTimeout="${SSH_TIMEOUT}" -o StrictHostKeyChecking=no \
        "${HOST}" 2>/dev/null || \
      log_debug "$(printf "${MSG_SSH_COPY_FAILED}" "${HOST}")"
    fi

    log_debug "$(printf "${MSG_SSH_RETRY_FAILED}" "$(( attempt + 1 ))" "${max_retries}" "${err_msg}")"
    (( attempt+=1 ))
  done

  # KCOV_EXCL_START — kcov cannot instrument multi-line command substitution
  log_error "$(
    printf "${MSG_SSH_FINAL_FAILURE}\n" "${max_retries}"
    printf '  %s\n' "${err_msgs[@]}"
  )"
  # KCOV_EXCL_STOP
}

# Selects the best available file transfer tool.
#
# Checks for rsync, scp, and sftp in order. For rsync, also verifies the
# binary exists on the remote host (rsync requires both sides).
# Sets GET_LOG_TOOL to the first usable tool found.
get_tools_checker() {
  local -r -a tools=("rsync" "scp" "sftp")
  local tool=""
  for tool in "${tools[@]}"; do
    if ! pkg_install_handler "${tool}"; then
      continue # KCOV_EXCL_LINE
    fi

    # rsync requires the binary on BOTH local and remote hosts
    if [[ "${tool}" == "rsync" && "${HOST}" != "local" ]]; then
      # KCOV_EXCL_START — only triggered when remote lacks rsync
      if ! execute_cmd "command -v rsync >/dev/null 2>&1"; then
        log_warn "${MSG_RSYNC_NOT_AVAILABLE}"
        continue
      fi
      # KCOV_EXCL_STOP
    fi

    GET_LOG_TOOL="${tool}"
    return 0
  done

  log_error "$(printf "${MSG_NO_TRANSFER_TOOLS}" "${tools[*]}")" # KCOV_EXCL_LINE
}

# Parses a special string.
#
# This function parses a special string in the format `<type:string>` and
# resolves it to a value.
#
# Arguments:
#   input: The special string to parse.
#
# Sets:
#   REPLY_TYPE: The type of the token (env, cmd, date, suffix).
#   REPLY_STR:  The resolved string value.
special_string_parser() {
  local -r input="${1:?"${FUNCNAME[0]} need input string."}"; shift

  if [[ ! "${input}" == *:* ]]; then
    log_error "$(printf "${MSG_INVALID_SPECIAL_STRING}" "${input}")"
  fi

  REPLY_TYPE="${input%%:*}"
  local str="${input#"${REPLY_TYPE}":}"
  log_debug "Parsed special string - type: ${REPLY_TYPE}, string: ${str}"

  if [[ ${REPLY_TYPE} == "env"  || ${REPLY_TYPE} == "cmd" ]]; then
    get_remote_value "${REPLY_TYPE}" "${str}"
    REPLY_STR="${REPLY}"
  elif [[ ${REPLY_TYPE} == "date" || ${REPLY_TYPE} == "suffix" ]]; then
    REPLY_STR="${str}"
  else
    log_error "$(printf "${MSG_UNKNOWN_SPECIAL_STRING}" "${REPLY_TYPE}")"
  fi

  log_debug "Resolved string: ${REPLY_STR}"
}

# Handles a string containing special tokens.
#
# This function takes a string, finds all special tokens in the format
# `<...>`, and replaces them with their resolved values.
#
# Arguments:
#   str: The string to process.
#
# Sets:
#   REPLY_PATH:   The path part of the string (before ::).
#   REPLY_PREFIX: The prefix part of the string (after ::).
#   REPLY_SUFFIX: The suffix filter (from <suffix:> token), or empty.
string_handler() {
  local str="${1:?"${FUNCNAME[0]} need string."}"; shift
  REPLY_SUFFIX=""
  local -a date_tokens=()
  local i=0

  log_debug "Original string: ${str}"
  while [[ "${str}" =~ (<[^<>]*>) ]]; do
    local token="${BASH_REMATCH[1]}"

    # special case for date, need to process later
    if [[ "${token}" == "<date:"*">" ]]; then
      log_debug "Date token process later: ${token}"
      date_tokens+=("${token}")
      str="${str//${token}/__DATE_TOKEN_${i}__}"
      (( i+=1 ))
      continue
    fi

    # normal case, replace directly
    log_debug "Processing token: ${token}"
    special_string_parser "${token:1:-1}"
    if [[ "${REPLY_TYPE}" == "suffix" ]]; then
      REPLY_SUFFIX="${REPLY_STR}"
      log_debug "Suffix set to: ${REPLY_SUFFIX}"
      str="${str//${token}/}"
      continue
    fi
    str="${str//${token}/${REPLY_STR}}"
  done

  local j
  for j in "${!date_tokens[@]}"; do
    str="${str/__DATE_TOKEN_${j}__/${date_tokens["${j}"]}}"
  done

  REPLY_PATH="${str%%::*}"
  REPLY_PREFIX="${str##*::}"
}

# Finds files matching a name pattern and time range on local or remote host.
#
# For config files (no <date:> token), returns all matches directly.
# For dated files, extracts timestamps from filenames, filters by range,
# and expands boundaries by +/-1 to catch edge cases.
#
# Arguments:
#   folder_path: Directory to search in.
#   file_prefix: Filename pattern before the date token (may contain <date:>).
#   file_suffix: Filename pattern after the date token (may contain <date:>).
#   start_time:  Range start in YYYYmmdd-HHMMSS format.
#   end_time:    Range end in YYYYmmdd-HHMMSS format.
#
# Sets:
#   REPLY_FILES: Array of matched file paths.
file_finder() {
  local -r folder_path="${1:?"${FUNCNAME[0]} need path."}"; shift
  local file_prefix="${1:-}"; shift
  local file_suffix="${1:-}"; shift
  local start_time="${1:?"${FUNCNAME[0]} need start time."}"; shift
  local end_time="${1:?"${FUNCNAME[0]} need end time."}"; shift

  log_verbose "${FUNCNAME[0]} input: Path=${folder_path}, Prefix=${file_prefix}"

  local token="" format_position=""
  if [[ "${file_prefix}" =~ (<date:[^<>]*>) ]]; then
    token="${BASH_REMATCH[1]}"
    format_position="prefix"
    file_prefix="${file_prefix//${token}/}"
  elif [[ "${file_suffix}" =~ (<date:[^<>]*>) ]]; then
    token="${BASH_REMATCH[1]}"
    format_position="suffix"
    file_suffix="${file_suffix//${token}/}"
  fi
  log_debug "Date token position: ${format_position}, content: ${token}"

  local format=""
  if [[ -n "${token}" ]]; then
    special_string_parser "${token:1:-1}"
    format="${REPLY_STR}"
  fi

  local find_cmd
  printf -v find_cmd "find %q -maxdepth 1 -type f -name %q 2>/dev/null | sort" \
    "${folder_path}" "${file_prefix}${file_suffix}"
  readonly find_cmd

  # get file list
  local -a raw_files=()
  if ! mapfile -t raw_files < <(execute_cmd "${find_cmd}"); then
    REPLY_FILES=() # KCOV_EXCL_LINE
    return 0 # KCOV_EXCL_LINE
  fi

  # [1] Configuration Files Direct Pass
  if [[ -z "${token}" ]]; then
    REPLY_FILES=("${raw_files[@]}")
    return 0
  fi

  # [2] Date Format Preparation
  local formatted_start_ts="" formatted_end_ts=""
  if [[ -n "${format}" ]]; then
    date_format "${start_time}" "${format}"
    formatted_start_ts="${REPLY}"
    date_format "${end_time}" "${format}"
    formatted_end_ts="${REPLY}"
  else
    formatted_start_ts="${start_time}"
    formatted_end_ts="${end_time}"
  fi

  # [3] Regex Extraction
  local regex_pattern=""
  local char i
  for (( i=0; i<${#formatted_start_ts}; i++ )); do
    char="${formatted_start_ts:$i:1}"
    if [[ "$char" =~ [0-9] ]]; then regex_pattern+="[0-9]"; else regex_pattern+="${char}"; fi
  done

  local -a all_files=()
  local -a file_timestamps=()
  for i in "${!raw_files[@]}"; do
    local filename="${raw_files[${i}]##*/}"
    if [[ "${filename}" =~ (${regex_pattern}) ]]; then
      all_files+=("${raw_files[i]}")
      file_timestamps+=("${BASH_REMATCH[1]}")
    fi
  done

  if [[ ${#all_files[@]} -eq 0 ]]; then
    REPLY_FILES=()
    return 0
  fi

  # [4] Unique Timestamps & Index Boundaries
  local -a uniq_ts=()
  local ts="" last_ts=""
  for ts in "${file_timestamps[@]}"; do
    if [[ "$ts" != "$last_ts" ]]; then
      uniq_ts+=( "$ts" )
      last_ts="$ts"
    fi
  done

  local s_idx=-1 e_idx=-1
  for i in "${!uniq_ts[@]}"; do
    if [[ $s_idx -eq -1 ]] && [[ "${uniq_ts[i]}" > "${formatted_start_ts}" || "${uniq_ts[i]}" == "${formatted_start_ts}" ]]; then
      s_idx=$i
    fi
    if [[ "${uniq_ts[i]}" < "${formatted_end_ts}" || "${uniq_ts[i]}" == "${formatted_end_ts}" ]]; then
      e_idx=$i
    fi
  done

  # [5] Robust Range Expansion logic
  # Case A: Found no start point? (All files are older than range)
  if [[ $s_idx -eq -1 ]]; then
     # Try to see if we can pick up from the end? No, means everything is outside.
     # But if e_idx is valid, it means we have files OLDER than end_time.
     # So start from index 0.
     if [[ $e_idx -ne -1 ]]; then s_idx=0; fi
  fi

  # Case B: Found no end point? (All files are newer than range, or start point is very late)
  if [[ $e_idx -eq -1 ]]; then
     # If we have a start point, it means files exist NEWER than start_time.
     # So end at the last file.
     if [[ $s_idx -ne -1 ]]; then e_idx=$(( ${#uniq_ts[@]} - 1 )); fi
  fi

  # Case C: Still invalid?
  if [[ $s_idx -eq -1 || $e_idx -eq -1 || $s_idx -gt $e_idx ]]; then
    log_warn "$(printf "${MSG_NO_FILES_IN_RANGE}" "${formatted_start_ts}" "${formatted_end_ts}")"
    REPLY_FILES=()
    return 0
  fi

  # Apply Expansion (Safely)
  if [[ $s_idx -gt 0 ]]; then (( s_idx-- )); fi
  if [[ $e_idx -lt $(( ${#uniq_ts[@]} - 1 )) ]]; then (( e_idx++ )); fi

  local final_start_val="${uniq_ts[s_idx]}"
  local final_end_val="${uniq_ts[e_idx]}"

  log_debug "Expanded Index Range: ${s_idx} to ${e_idx} (Values: ${final_start_val} ~ ${final_end_val})"

  # [6] Final Selection
  local -a selected=()
  for i in "${!all_files[@]}"; do
    ts="${file_timestamps[i]}"
    # Use simple string comparison for selection
    if [[ "$ts" > "$final_start_val" || "$ts" == "$final_start_val" ]] && \
       [[ "$ts" < "$final_end_val"   || "$ts" == "$final_end_val" ]]; then
      selected+=( "${all_files[${i}]}" )
    fi
  done

  REPLY_FILES=("${selected[@]}")
  log_info "$(printf "${MSG_FILES_SELECTED}" "${#REPLY_FILES[@]}" "${#all_files[@]}")"
}

# Creates the output folder.
#
# This function creates the output folder for the logs. The folder name is
# constructed from the `SAVE_FOLDER` variable, the hostname and the current date.
folder_creator() {
  local combined
  if ! combined=$(execute_cmd "printf '%s_%s' \"\$(hostname)\" \"\$(date +%Y%m%d-%H%M%S)\""); then
    log_error "$(printf "${MSG_HOSTNAME_DATE_FAILED}" "${HOST}")" # KCOV_EXCL_LINE
  fi

  SAVE_FOLDER="${SAVE_FOLDER}_${combined}"
  create_folder "${SAVE_FOLDER}"
}

# Writes a summary of user inputs and LOG_PATHS to script.log in SAVE_FOLDER.
save_script_data() {
  # KCOV_EXCL_START — kcov cannot instrument array literal lines
  local -a string_array=(
    "Host: ${HOST}"
    "Time range: ${START_TIME} ~ ${END_TIME}"
    "Using tool: ${GET_LOG_TOOL}"
    "Saving logs to folder: ${SAVE_FOLDER}"
    )
  # KCOV_EXCL_STOP

  log_info "${MSG_USER_INPUTS_SUMMARY}"

  local escaped_folder="${SAVE_FOLDER//\'/\'\\\'\'}"
  local script_log="'${escaped_folder}/script.log'"

  local remote_cmd=""
  remote_cmd+="printf '%s\n' 'User Inputs:' >> ${script_log}; "

  local string escaped
  for string in "${string_array[@]}"; do
    log_info "  ${string}"
    escaped="${string//\'/\'\\\'\'}"
    remote_cmd+="printf '  %s\n' '${escaped}' >> ${script_log}; "
  done

  remote_cmd+="printf '\nLOG_PATHS:\n' >> ${script_log}; "

  for string in "${LOG_PATHS[@]}"; do
    escaped="${string//\'/\'\\\'\'}"
    remote_cmd+="printf '  %s\n' '${escaped}' >> ${script_log}; "
  done

  log_info "-------------------------------"

  execute_cmd "${remote_cmd}"
}

# Removes the temporary log folder from the local or remote host.
#
# This function is typically used as a cleanup task (e.g., in a trap) to ensure
# that the temporary directory created during the process is removed after
# the script finishes or is interrupted.
#
# Globals:
#   SAVE_FOLDER: The path of the folder to be removed.
file_cleaner() {
  close_log_file
  if [[ -z "${SAVE_FOLDER}" ]]; then
    log_debug "${MSG_NO_SAVE_FOLDER}"
    return 0
  fi

  local rm_cmd
  printf -v rm_cmd "rm -rf %q" "${SAVE_FOLDER}"
  readonly rm_cmd

  if ! execute_cmd "${rm_cmd}"; then
    log_warn "$(printf "${MSG_FOLDER_REMOVE_FAILED}" "${SAVE_FOLDER}")" # KCOV_EXCL_LINE
  else
    log_debug "$(printf "${MSG_FOLDER_REMOVED}" "${SAVE_FOLDER}")"
  fi
}

# Copies matched files into the SAVE_FOLDER on local or remote host.
#
# Strips /home/<user>/ prefix from paths to keep output structure clean.
# Uses xargs with null-delimited input to handle filenames safely.
#
# Arguments:
#   log_path: The resolved source directory path.
#   ...:      File paths to copy.
file_copier() {
  local log_path="${1:?"${FUNCNAME[0]} need log path."}"; shift
  local -a fc_log_files=("$@")

  log_verbose "${FUNCNAME[0]} input is: "
  log_verbose "  log_path: ${log_path}"
  log_verbose "  files count: ${#fc_log_files[@]}"
  log_verbose "  SAVE_FOLDER: ${SAVE_FOLDER}"
  log_verbose "  HOST: ${HOST}"

  if [[ ${#fc_log_files[@]} -eq 0 ]]; then
    log_warn "$(printf "${MSG_NO_FILES_TO_COPY}" "${log_path}")"
    return 0
  fi

  if [[ "${log_path}" == /home/*/*  ]]; then
    log_path="${log_path#/home/*/}"
  fi

  local save_path="${SAVE_FOLDER}/${log_path#*:}"
  create_folder "${save_path}"

  local -a cp_opts=("-r")
  if [[ "${VERBOSE:-0}" -ge 1 ]]; then
    cp_opts+=("-v")
  fi

  # Construct the xargs command
  local xargs_cmd
  printf -v xargs_cmd "xargs -0 -r cp %s -t %q" "${cp_opts[*]}" "${save_path}/"

  # Execute by piping the array directly (avoiding variable truncation)
  if ! execute_cmd_from_array "${xargs_cmd}" "${fc_log_files[@]}"; then
    log_error "$(printf "${MSG_COPY_FAILED}" "${save_path}")"
  fi

  log_verbose "--------------------"
}

# Transfers SAVE_FOLDER from the remote host to the local machine.
#
# Uses rsync, scp, or sftp (as determined by get_tools_checker).
# Automatically retries up to TRANSFER_MAX_RETRIES times on failure,
# with TRANSFER_RETRY_DELAY seconds between attempts.
file_sender() {
  local -r tool="${GET_LOG_TOOL}"
  # Always show transfer progress; add verbose detail only with -v
  # --partial: keep partially transferred files (resume on retry)
  # --timeout: rsync-level I/O timeout (complements SSH ServerAliveInterval)
  local -a rsync_flags=("-a" "-z" "--progress" "--partial" "--timeout=60")
  local -a scp_flags=("-p" "-r")
  local sftp_progress="progress\n" sftp_output="/dev/stdout"

  # KCOV_EXCL_START — file_sender only runs in remote integration tests
  if [[ "${VERBOSE:-0}" -ge 1 ]]; then
    rsync_flags+=("-v")
    scp_flags+=("-v")
  fi
  # KCOV_EXCL_STOP

  local local_save_folder
  if [[ "${SAVE_FOLDER}" == /* ]]; then
    local_save_folder="${SAVE_FOLDER}"
  else
    local_save_folder="${HOME}/${SAVE_FOLDER}"
  fi
  log_info "$(printf "${MSG_LOCAL_DESTINATION}" "${local_save_folder}")"

  local remote_esc
  printf -v remote_esc '%q' "${SAVE_FOLDER}"

  if ! execute_cmd "test -d ${remote_esc}"; then
    log_error "$(printf "${MSG_REMOTE_NOT_FOUND}" "${SAVE_FOLDER}")"
  fi

  mkdir -p "${local_save_folder}"

  local folder_size=""
  folder_size=$(execute_cmd "du -sh ${remote_esc} | awk '{print \$1}'")
  log_info "$(printf "${MSG_REMOTE_FOLDER_SIZE}" "${SAVE_FOLDER}" "${folder_size}")"

  # KCOV_EXCL_START — transfer loop requires real SSH/rsync/scp/sftp
  local attempt=0
  while (( attempt < TRANSFER_MAX_RETRIES )); do
    local transfer_ok=false

    case "${tool}" in
      rsync)
        local remote_path="${HOST}:${remote_esc}/"
        # -T: no pseudo-terminal; LogLevel=ERROR: suppress SSH banner/motd output
        # that would otherwise corrupt the rsync protocol stream
        local ssh_cmd_str="ssh -T -o LogLevel=ERROR ${SSH_OPTS[*]}"

        rsync "${rsync_flags[@]}" -e "${ssh_cmd_str}" \
          "${remote_path}" "${local_save_folder}/" \
          && transfer_ok=true
        ;;
      scp)
        local remote_path="${HOST}:${remote_esc}"

        scp "${scp_flags[@]}" "${SSH_OPTS[@]}" \
          "${remote_path}" "${local_save_folder}/" \
          && transfer_ok=true
        ;;
      sftp)
        local local_esc
        printf -v local_esc '%q' "${local_save_folder}"

        printf '%sget -r %s %s\n' "${sftp_progress}" "${remote_esc}" "${local_esc}" | \
          sftp "${SSH_OPTS[@]}" \
          "${HOST}" > "${sftp_output}" \
          && transfer_ok=true
        ;;
    *)
      log_error "$(printf "${MSG_UNSUPPORTED_TOOL}" "${tool}")"
      ;;
    esac

    if [[ "${transfer_ok}" == "true" ]]; then
      break
    fi

    (( attempt++ ))
    if (( attempt < TRANSFER_MAX_RETRIES )); then
      log_warn "$(printf "${MSG_TRANSFER_RETRY}" "${tool}" "${attempt}" "${TRANSFER_MAX_RETRIES}" "${TRANSFER_RETRY_DELAY}")"
      sleep "${TRANSFER_RETRY_DELAY}"
    else
      log_warn "$(printf "${MSG_TRANSFER_FAILED}" "${tool}" "${TRANSFER_MAX_RETRIES}")"
      log_warn "$(printf "${MSG_REMOTE_PRESERVED}" "${HOST}" "${SAVE_FOLDER}")"
      log_warn "${MSG_RETRIEVE_MANUALLY}"
      return 1
    fi
  done
  # KCOV_EXCL_STOP
}

# Main function for getting the logs.
#
# This function iterates over the `LOG_PATHS` array, finds the log files, and
# copies them to the output folder.
get_log() {
  local log_path=""
  local total=${#LOG_PATHS[@]}
  local idx=0

  for log_path in "${LOG_PATHS[@]}"; do
    (( idx++ ))

    log_info "$(printf "${MSG_PROCESSING}" "${idx}" "${total}" "${log_path}")"
    string_handler "${log_path}"
    local path="${REPLY_PATH}" prefix="${REPLY_PREFIX}" suffix="${REPLY_SUFFIX}"

    file_finder "${path}" "${prefix}" "${suffix}" "${START_TIME}" "${END_TIME}"
    local -a files=("${REPLY_FILES[@]+"${REPLY_FILES[@]}"}")

    if [[ "${#files[@]}" -eq 0 ]]; then
      log_warn "$(printf "${MSG_NO_FILES_FOUND}" "${idx}" "${total}")"
      continue
    fi

    log_info "$(printf "${MSG_FOUND_COPYING}" "${idx}" "${total}" "${#files[@]}")"
    file_copier "${path}" "${files[@]}"
  done
}

# Main function.
#
# This is the main function of the script. It parses the command-line
# options, handles the host and time selection, checks for the SSH
# connection, and then gets the logs.
main() {
  option_parser "$@"

  # Resolve language: --lang > $LANG > default en
  if [[ -z "${LANG_CODE}" ]]; then
    case "${LANG:-}" in
      zh_TW*) LANG_CODE="zh-TW" ;; zh_CN*|zh_SG*) LANG_CODE="zh-CN" ;;
      ja*) LANG_CODE="ja" ;; *) LANG_CODE="en" ;;
    esac
  fi
  load_lang

  log_info "${MSG_STEP1}"
  host_handler

  log_info "${MSG_STEP2}"
  time_handler

  if [[ "${HOST}" != "local" ]]; then
    log_info "${MSG_STEP3_SSH}"
    ssh_handler
    get_tools_checker
  else
    log_info "${MSG_STEP3_LOCAL}"
    GET_LOG_TOOL="local"
  fi

  log_info "${MSG_STEP4}"
  folder_creator
  init_log_file

  if [[ "${HOST}" == "local" ]]; then
    trap file_cleaner SIGINT SIGTERM
  else
    trap file_cleaner EXIT SIGINT SIGTERM
  fi

  save_script_data
  get_log

  if [[ "${HOST}" != "local" ]]; then
    log_info "$(printf "${MSG_STEP5_TRANSFER}" "${GET_LOG_TOOL}")" # KCOV_EXCL_LINE
    # KCOV_EXCL_START — file_sender only runs in remote integration tests
    if ! file_sender; then
      trap - EXIT
      close_log_file
      exit 1
    fi
    # KCOV_EXCL_STOP
  else
    log_info "${MSG_STEP5_LOCAL}"
  fi

  log_info "${MSG_SUCCESS}"
  close_log_file
}

# Allow sourcing without executing main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
