#!/bin/bash
# English message catalog for pack_log.sh

# --- Help text ---
# shellcheck disable=SC2034
MSG_HELP_USAGE='Usage: %s [options]'
MSG_HELP_OPTIONS='  Options:'
MSG_HELP_NUMBER='    -n, --number                  Host number (1-%d)'
MSG_HELP_USERHOST='    -u, --userhost <user@host>    User and host (e.g. user@host)'
MSG_HELP_LOCAL='    -l, --local                   Use local machine'
MSG_HELP_START='    -s, --start <YYYYmmdd-HHMMSS>  Start time (e.g. 20260101-000000)'
MSG_HELP_END='    -e, --end <YYYYmmdd-HHMMSS>    End time (e.g. 20260101-235959)'
MSG_HELP_OUTPUT='    -o, --output <path>           Output folder path'
MSG_HELP_LANG='    --lang <code>                 Language (en, zh-TW, zh-CN, ja)'
MSG_HELP_VERBOSE='    -v, --verbose                 Enable verbose output'
MSG_HELP_VERY_VERBOSE='    -vv, --very-verbose           Enable very verbose output (debug)'
MSG_HELP_EXTRA_VERBOSE='    -vvv, --extra-verbose         Enable extra verbose output (set -x)'
MSG_HELP_HELP='    -h, --help                    Show this help message and exit'
MSG_HELP_VERSION='    --version                     Show version and exit'

# --- Package / sudo ---
MSG_CHECKING_SUDO='Checking sudo access.'
MSG_PKG_ALREADY_INSTALLED='Package %s already installed.'
MSG_PKG_NOT_FOUND='Package %s not found, installing...'
MSG_NO_SUDO_ACCESS='No sudo access to install %s.'
MSG_PKG_INSTALL_FAILED='Failed to install package %s.'

# --- Date format ---
MSG_INVALID_DATE_FORMAT='Invalid date format: %s'
MSG_DATE_FORMAT_FAILED='Failed to format date: %s'

# --- Remote value / token ---
MSG_UNKNOWN_TOKEN_TYPE='Unknown type: %s'
MSG_COMMAND_FAILED='Command failed: %s'
MSG_INVALID_SPECIAL_STRING='Invalid special string format: %s'
MSG_UNKNOWN_SPECIAL_STRING='Unknown special string type: %s'

# --- Folder ---
MSG_FOLDER_CREATE_FAILED='Failed to create folder: %s'
MSG_HOSTNAME_DATE_FAILED='Failed to get hostname/date from %s'

# --- Host handler ---
MSG_HOST_USING_LOCAL='Using local machine as host'
MSG_HOST_PROMPT='Enter local, number (1-%d) or user@host: '
MSG_INVALID_INPUT='Invalid input: %s'
MSG_HOST_NUMBER_RANGE='Number must be between 1 and %d'
MSG_INVALID_USERHOST='Invalid user@host format: %s'

# --- Time handler ---
MSG_TIME_PROMPT='Enter %s (YYYYmmdd-HHMMSS): '
MSG_INVALID_TIME_FORMAT='Invalid %s format: %s'
MSG_START_BEFORE_END='start_time (%s) must be before end_time (%s)'

# --- SSH handler ---
MSG_SSH_ATTEMPT='Attempting SSH connection to %s (attempt %d/%d)...'
MSG_SSH_SUCCESS='SSH connection to %s successful'
MSG_SSH_KEY_EXISTS='SSH key %s exists'
MSG_SSH_PERMISSION_DENIED='SSH key permission denied, will attempt to copy key.'
MSG_SSH_HOST_CHANGED='SSH host identification has changed, removing old key.'
MSG_SSH_FAILED='SSH connection failed: %s'
MSG_SSH_KEY_NOT_FOUND='SSH key %s does not exist'
MSG_SSH_KEY_CREATING='Creating new SSH key'
MSG_SSH_KEY_CREATE_WITH='SSH key %s not found, creating with %s...'
MSG_SSH_KEY_CREATE_FAILED='Failed to create SSH key %s'
MSG_SSH_HOST_KEY_REMOVE='Removing existing SSH host key for %s.'
MSG_SSH_HOST_KEY_ADD='Adding %s to known hosts.'
MSG_SSH_PRIVATE_NOT_FOUND='Private key not found: %s'
MSG_SSH_PUBLIC_NOT_FOUND='Public key not found: %s'
MSG_SSH_KEY_INVALID='Invalid private key: %s'
MSG_SSH_KEY_MISMATCH='Public key does not match private key.'
MSG_SSH_COPY_FAILED='Failed to copy SSH key to %s.'
MSG_SSH_RETRY_FAILED='SSH retry %d/%d failed: %s'
MSG_SSH_FINAL_FAILURE='SSH connection failed after %d retries:'

# --- Tools checker ---
MSG_RSYNC_NOT_AVAILABLE='rsync not available on remote host, trying next tool...'
MSG_NO_TRANSFER_TOOLS='No file transfer tools (%s) available.'

# --- File operations ---
MSG_NO_FILES_IN_RANGE='No files found intersecting the time range %s ~ %s.'
MSG_FILES_SELECTED='Selected %d files from %d candidates.'
MSG_USER_INPUTS_SUMMARY='User Inputs Summary:'
MSG_NO_SAVE_FOLDER='No SAVE_FOLDER defined, skipping cleanup.'
MSG_FOLDER_REMOVE_FAILED='Failed to remove remote folder: %s'
MSG_FOLDER_REMOVED='Remote folder %s removed successfully.'
MSG_NO_FILES_TO_COPY='No files to copy for %s'
MSG_COPY_FAILED='Failed to copy files to %s'
MSG_LOCAL_DESTINATION='Local destination folder: %s'
MSG_REMOTE_NOT_FOUND='Remote folder not found: %s'
MSG_REMOTE_FOLDER_SIZE='Remote folder %s size is: %s'
MSG_UNSUPPORTED_TOOL='Unsupported file transfer tool: %s'
MSG_TRANSFER_RETRY='%s failed (attempt %d/%d), retrying in %ds...'
MSG_TRANSFER_FAILED='%s failed after %d attempts.'
MSG_REMOTE_PRESERVED='Remote folder preserved: %s:%s'
MSG_RETRIEVE_MANUALLY='Please retrieve manually and delete when done.'

# --- get_log ---
MSG_PROCESSING='[%d/%d] Processing: %s'
MSG_NO_FILES_FOUND='[%d/%d] No files found.'
MSG_FOUND_COPYING='[%d/%d] Found %d files, copying...'

# --- Main steps ---
MSG_STEP1='=== Step 1/5: Resolving target host ==='
MSG_STEP2='=== Step 2/5: Validating time range ==='
MSG_STEP3_SSH='=== Step 3/5: Establishing SSH connection ==='
MSG_STEP3_LOCAL='=== Step 3/5: Local mode (skipping SSH) ==='
MSG_STEP4='=== Step 4/5: Collecting log files ==='
MSG_STEP5_TRANSFER='=== Step 5/5: Transferring files to local (%s) ==='
MSG_STEP5_LOCAL='=== Step 5/5: Files collected locally ==='
MSG_SUCCESS='Packaging log completed successfully.'
