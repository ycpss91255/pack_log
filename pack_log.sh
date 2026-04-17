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
#   # Pick a host by number from the HOSTS array
#   ./pack_log.sh -n 1 -s 260101-0000 -e 260101-2359
#
#   # Local mode — collect from this machine, no SSH
#   ./pack_log.sh -l -s 260101-0000 -e 260101-2359
#
#   # Dry-run — list files that would be collected, no copy/transfer/archive
#   ./pack_log.sh -n 1 -s 260101-0000 -e 260101-2359 --dry-run
#
# Run with --help for the full option reference.
#
# Author: Yunchien.chen <yunchien.chen@coretronic-robotics.com>
# Date: 2026-04-15
# Version: 1.8.0

# shellcheck disable=SC2059  # i18n: MSG_* variables used as printf format strings by design
# shellcheck disable=SC2029  # SSH commands piped via stdin, not affected
# shellcheck disable=SC2016  # Single-quoted <env:> tokens are resolved by string_handler, not bash

set +u 2>/dev/null
declare _PACK_LOG_SCRIPT_NAME
_PACK_LOG_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}" .sh)"
readonly _PACK_LOG_SCRIPT_NAME

set -euo pipefail

# ==============================================================================
# User Configuration (frequently adjusted per deployment site)
# ==============================================================================

# Target hosts: "display_name::user@host"
#
# How to get host information:
#   1. On the remote machine, run: hostname -I  (to get IP)
#   2. On the remote machine, run: whoami       (to get username)
#   3. Test connection: ssh user@IP
#   4. Add entry below: "my-robot::user@IP"
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

# Log paths format: consecutive triplets of (PATH, FILE_PATTERN, FLAGS).
#
# Examples:
#   "<env:HOME>/config"                "node_config.yaml"                      ""
#   "<env:HOME>/log_core"              "app.<cmd:hostname>.log.<date:%Y%m%d-%H%M%S>*"  ""
#   "/var/log"                         "syslog*"                               "<sudo>"
#   "<env:HOME>/log_core"              "app.*.<date:%Y%m%d-%H%M%S>*"           "<sudo>"

# Coretronic path shortcuts (non-Docker)
# shellcheck disable=SC2034
declare COREROBOT_CORETRONIC_AMR_NAVI_INSTALL="<env:HOME>/coretronic_amr_navi_install"
# shellcheck disable=SC2034
declare COREROBOT_STORAGE="<env:HOME>/core_storage"
# shellcheck disable=SC2034
declare COREROBOT_LOG="<env:HOME>/log"
# shellcheck disable=SC2034
declare COREROBOT_LOG_CORE="<env:HOME>/log_core"
# shellcheck disable=SC2034
declare COREROBOT_LOG_DATA="<env:HOME>/log_data"
# shellcheck disable=SC2034
declare COREROBOT_LOG_SLAM="<env:HOME>/log_slam"

# Coretronic path shortcuts (Docker)
declare COREROBOT_DOCKER_HOME="<env:HOME>/ros-docker/AMR/myuser"
# shellcheck disable=SC2034
declare COREROBOT_DOCKER_CORETRONIC_AMR_NAVI_INSTALL="${COREROBOT_DOCKER_HOME}/coretronic_amr_navi_install"
# shellcheck disable=SC2034
declare COREROBOT_DOCKER_STORAGE="${COREROBOT_DOCKER_HOME}/core_storage"
# shellcheck disable=SC2034
declare COREROBOT_DOCKER_LOG="${COREROBOT_DOCKER_HOME}/log"
# shellcheck disable=SC2034
declare COREROBOT_DOCKER_LOG_CORE="${COREROBOT_DOCKER_HOME}/log_core"
# shellcheck disable=SC2034
declare COREROBOT_DOCKER_LOG_DATA="${COREROBOT_DOCKER_HOME}/log_data"
# shellcheck disable=SC2034
declare COREROBOT_DOCKER_LOG_SLAM="${COREROBOT_DOCKER_HOME}/log_slam"

declare -a LOG_PATHS=(
  # # PATH                                                                  FILE_PATTERN                                                      FLAGS
  # # AvoidStop (pana-04, local test with symlink dirs)
  # "<env:HOME>/Desktop/pack_log/log/avoid/core_storage/default"           "uimap.png"                                                        ""
  # "<env:HOME>/Desktop/pack_log/log/avoid/core_storage/default2"          "uimap.yaml"                                                       ""
  # "<env:HOME>/Desktop/pack_log/log/avoid/log/AvoidStop_<date:%Y-%m-%d>"  "<date:%Y-%m-%d-%H.%M.%S>_*_avoid.png"                             ""
  # "<env:HOME>/Desktop/pack_log/log/avoid/log_core"                       "corenavi_auto.pana-04.myuser.log.INFO.<date:%Y%m%d-%H%M%S>*"      ""
  # "<env:HOME>/Desktop/pack_log/log/avoid/log_slam/record"                "coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*.rec"                        ""

  # # Panasonic — LiDAR Detection shelf log path (docker)
  # "${COREROBOT_DOCKER_LOG_CORE}"                      "corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*"  ""
  # "${COREROBOT_DOCKER_LOG_DATA}/lidar_detection"      "detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*.dat"                  ""
  # "${COREROBOT_DOCKER_LOG_DATA}/lidar_detection"      "detect_shelf_<date:%Y%m%d%H%M%S>*.pcd"                                   ""
  # "${COREROBOT_DOCKER_LOG_DATA}/lidar_detection/glog" "detect_shelf_node-DetectShelf-<date:%Y%m%d-%H%M%S>*"                     ""
  # "${COREROBOT_DOCKER_LOG_SLAM}"                      "coreslam_2D_<date:%s>*.log"                                              ""
  # "${COREROBOT_DOCKER_LOG_SLAM}/record"               "coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*.rec"                               ""
  # "${COREROBOT_DOCKER_STORAGE}"                       "node_config.yaml"                                                        ""
  # "${COREROBOT_DOCKER_STORAGE}"                       "shelf.ini"                                                               ""
  # "${COREROBOT_DOCKER_STORAGE}"                       "external_param.launch"                                                   ""
  # "${COREROBOT_DOCKER_STORAGE}"                       "run_config.yaml"                                                         ""

  # Panasonic — 2D LiDAR AvoidStop and EmergencyStop log path (docker)
  "${COREROBOT_DOCKER_STORAGE}/mapfile/default"            "uimap.png"                                                                  ""
  "${COREROBOT_DOCKER_STORAGE}/mapfile/default"            "uimap.yaml"                                                                 ""
  "${COREROBOT_DOCKER_LOG}/AvoidStop_<date:%Y-%m-%d>"      "<date:%Y-%m-%d-%H.%M.%S>_*_avoid.png"                                       ""
  "${COREROBOT_DOCKER_LOG}/EmergencyStop_<date:%Y-%m-%d>"  "<date:%Y-%m-%d-%H.%M.%S>_*_scan.png"                                        ""
  "${COREROBOT_DOCKER_LOG_CORE}"                           "corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*"     ""
  "${COREROBOT_DOCKER_LOG_SLAM}/record"                    "coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*.rec"                                  ""
  "${COREROBOT_DOCKER_LOG_DATA}/lidar_filter"              "lidar_filter_node.<cmd:hostname>.<env:USER>.log.*.<date:%Y%m%d-%H%M%S>*"    ""
  "${COREROBOT_DOCKER_LOG_DATA}/scan_fusion"               "scan_fusion_node.<cmd:hostname>.<env:USER>.log.*.<date:%Y%m%d-%H%M%S>*"     ""
  "${COREROBOT_DOCKER_LOG_DATA}/object_detector"           "object_detector_node.<cmd:hostname>.<env:USER>.log.*.<date:%Y%m%d-%H%M%S>*" ""

  # # Panasonic — Battery Changed fail log path (docker)
  # "${COREROBOT_DOCKER_LOG_CORE}"                 "corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*"  ""

  # # Ubuntu system and kernal logs
  # missing log path

  # # 2D LiDAR SLAM log path (docker)
  # "${COREROBOT_DOCKER_LOG_CORE}"        "corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*"  ""
  # "${COREROBOT_DOCKER_LOG_SLAM}"        "coreslam_2D_<date:%s>*.log"                                              ""
  # "${COREROBOT_DOCKER_LOG_SLAM}/record" "coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*.rec"                               ""

  # # ASE Us — LiDAR Detection pallet log path
  # "${COREROBOT_LOG_DATA}/lidar_detection"                                          "detect_pallet_node-DetectPallet_<date:%Y%m%d%H%M%S>*.dat"  ""
  # "${COREROBOT_LOG_DATA}/lidar_detection"                                          "detect_pallet_node-DetectPallet_<date:%Y%m%d%H%M%S>*.pcd"  ""
  # "${COREROBOT_LOG_DATA}/lidar_detection/glog"                                     "detect_pallet_node-DetectPallet-<date:%Y%m%d-%H%M%S>*"     ""
  # "${COREROBOT_CORETRONIC_AMR_NAVI_INSTALL}/share/lidar_detection_pkg/config"      "pallet.ini"                                                ""

  # # ASE Us - LiDAR Detection pallet log path (docker)
  # "${COREROBOT_DOCKER_LOG_CORE}"                      "corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*"  ""
  # "${COREROBOT_DOCKER_LOG_DATA}/lidar_detection"      "detect_pallet_node-DetectPallet_<date:%Y%m%d%H%M%S>*.dat"                ""
  # "${COREROBOT_DOCKER_LOG_DATA}/lidar_detection"      "detect_pallet_node-DetectPallet_<date:%Y%m%d%H%M%S>*.pcd"                ""
  # "${COREROBOT_DOCKER_LOG_DATA}/lidar_detection/glog" "detect_pallet_node-DetectPallet-<date:%Y%m%d-%H%M%S>*"                   ""
  # "${COREROBOT_DOCKER_LOG_SLAM}"                      "coreslam_2D_<date:%s>*.log"                                              ""
  # "${COREROBOT_DOCKER_LOG_SLAM}/record"               "coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*.rec"                               ""
  # "${COREROBOT_DOCKER_STORAGE}"                       "node_config.yaml"                                                        ""
  # "${COREROBOT_DOCKER_STORAGE}"                       "pallet.ini"                                                              ""
  # "${COREROBOT_DOCKER_STORAGE}"                       "external_param.launch"                                                   ""
  # "${COREROBOT_DOCKER_STORAGE}"                       "run_config.yaml"                                                         ""
  # "${COREROBOT_DOCKER_STORAGE}"                       "pallet.ini"                                                              ""

  # # ASE Us - LiDAR Detection pallet log path
  # "${COREROBOT_LOG_CORE}"                      "corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*"  ""
  # "${COREROBOT_LOG_DATA}/lidar_detection"      "detect_pallet_node-DetectPallet_<date:%Y%m%d%H%M%S>*.dat"                ""
  # "${COREROBOT_LOG_DATA}/lidar_detection"      "detect_pallet_node-DetectPallet_<date:%Y%m%d%H%M%S>*.pcd"                ""
  # "${COREROBOT_LOG_DATA}/lidar_detection/glog" "detect_pallet_node-DetectPallet-<date:%Y%m%d-%H%M%S>*"                   ""
  # "${COREROBOT_LOG_SLAM}"                      "coreslam_2D_<date:%s>*.log"                                              ""
  # "${COREROBOT_LOG_SLAM}/record"               "coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*.rec"                               ""
  # "${COREROBOT_STORAGE}"                       "node_config.yaml"                                                        ""
  # "${COREROBOT_STORAGE}"                       "pallet.ini"                                                              ""
  # "${COREROBOT_STORAGE}"                       "external_param.launch"                                                   ""
  # "${COREROBOT_STORAGE}"                       "run_config.yaml"                                                         ""
  # "${COREROBOT_STORAGE}"                       "pallet.ini"                                                              ""

)

declare SAVE_FOLDER="${_PACK_LOG_SCRIPT_NAME}"

# ==============================================================================
# Tunable Parameters (occasionally adjusted)
# ==============================================================================

declare SSH_KEY="${HOME}/.ssh/get_log"
declare SSH_TIMEOUT=3
declare TRANSFER_MAX_RETRIES=3
declare TRANSFER_RETRY_DELAY=5
declare TRANSFER_SIZE_WARN_MB=300
declare BANDWIDTH_LIMIT=0
declare FILE_TIME_TOLERANCE_MIN=30

# ==============================================================================
# Internal Variables (do not modify)
# ==============================================================================

declare -r VERSION="1.8.0"
declare VERBOSE=0
declare NUM="" HOST="" GET_LOG_TOOL=""
declare START_TIME="" END_TIME=""
declare LANG_CODE=""
declare DRY_RUN=false
declare LOG_FILE="" _LOG_FD=""

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

unset HAVE_SUDO_ACCESS

# Cache for resolved remote token values (avoids repeated SSH calls)
declare -gA _TOKEN_CACHE=()

# --- i18n ---
# Loads i18n messages based on LANG_CODE. All translations are embedded
# so the script has no external dependencies.
#
# Globals:
#   LANG_CODE  Read; selects which language block to load (en/zh-TW/zh-CN/ja).
#   MSG_*      Written; all localized message strings used by the script.
# Arguments:
#   None.
# Outputs:
#   None.
# Returns:
#   0 always (unknown LANG_CODE falls through to the English default).
# shellcheck disable=SC2034
load_lang() {
  case "${LANG_CODE}" in
    zh-TW)
      MSG_HELP_USAGE='用法: %s [選項]'
      MSG_HELP_OPTIONS='  選項:'
      MSG_HELP_NUMBER='    -n, --number                  主機編號 (1-%d)'
      MSG_HELP_USERHOST='    -u, --userhost <user@host>    使用者與主機 (例: user@host)'
      MSG_HELP_LOCAL='    -l, --local                   使用本機模式'
      MSG_HELP_START='    -s, --start <YYmmdd-HHMM>  起始時間 (例: 260101-0000)'
      MSG_HELP_END='    -e, --end <YYmmdd-HHMM>    結束時間 (例: 260101-2359)'
      MSG_HELP_OUTPUT='    -o, --output <路徑>           輸出資料夾路徑（支援 <num>, <name>, <date:fmt>）'
      MSG_HELP_LANG='    --lang <代碼>                 語言 (en, zh-TW, zh-CN, ja)'
      MSG_HELP_VERBOSE='    -v, --verbose                 啟用詳細輸出'
      MSG_HELP_VERY_VERBOSE='    -vv, --very-verbose           啟用更詳細輸出 (debug)'
      MSG_HELP_EXTRA_VERBOSE='    -vvv, --extra-verbose         啟用最詳細輸出 (set -x)'
      MSG_HELP_DRY_RUN='    --dry-run                     模擬執行，不複製或傳輸檔案'
      MSG_HELP_BWLIMIT='    --bwlimit <rate>              限制傳輸速度（預設 KB/s，支援 K/M/G[B] 後綴，0 = 不限制）'
      MSG_HELP_HELP='    -h, --help                    顯示此說明訊息並結束'
      MSG_HELP_VERSION='    --version                     顯示版本並結束'
      MSG_CHECKING_SUDO='正在檢查 sudo 權限。'
      MSG_PKG_ALREADY_INSTALLED='套件 %s 已安裝。'
      MSG_PKG_NOT_FOUND='找不到套件 %s，正在安裝...'
      MSG_NO_SUDO_ACCESS='沒有 sudo 權限來安裝 %s。'
      MSG_PKG_INSTALL_FAILED='安裝套件 %s 失敗。'
      MSG_INVALID_DATE_FORMAT='無效的日期格式: %s'
      MSG_DATE_FORMAT_FAILED='日期格式化失敗: %s'
      MSG_UNKNOWN_TOKEN_TYPE='未知的類型: %s'
      MSG_COMMAND_FAILED='指令執行失敗: %s'
      MSG_INVALID_SPECIAL_STRING='無效的特殊字串格式: %s'
      MSG_UNKNOWN_SPECIAL_STRING='未知的特殊字串類型: %s'
      MSG_TOKEN_NUM_NO_HOST='Token %s 需搭配 -n（主機編號），使用 -u 或 -l 時會被忽略'
      MSG_FOLDER_CREATE_FAILED='建立資料夾失敗: %s'
      MSG_HOSTNAME_DATE_FAILED='無法從 %s 取得主機名稱/日期'
      MSG_HOST_USING_LOCAL='使用本機作為目標主機'
      MSG_HOST_PROMPT='輸入 local、編號 (1-%d) 或 user@host: '
      MSG_INVALID_INPUT='無效的輸入: %s'
      MSG_HOST_NUMBER_RANGE='編號必須在 1 到 %d 之間'
      MSG_INVALID_USERHOST='無效的 user@host 格式: %s'
      MSG_TIME_PROMPT='輸入 %s (YYmmdd-HHMM): '
      MSG_INVALID_TIME_FORMAT='無效的 %s 格式: %s'
      MSG_START_BEFORE_END='起始時間 (%s) 必須早於結束時間 (%s)'
      MSG_SSH_ATTEMPT='正在嘗試 SSH 連線到 %s (第 %d/%d 次)...'
      MSG_SSH_SUCCESS='SSH 連線到 %s 成功'
      MSG_SSH_KEY_EXISTS='SSH 金鑰 %s 存在'
      MSG_SSH_PERMISSION_DENIED='SSH 金鑰權限被拒，將嘗試複製金鑰。'
      MSG_SSH_HOST_CHANGED='SSH 主機識別已變更，正在移除舊金鑰。'
      MSG_SSH_FAILED='SSH 連線失敗: %s'
      MSG_SSH_KEY_NOT_FOUND='SSH 金鑰 %s 不存在'
      MSG_SSH_KEY_CREATING='正在建立新的 SSH 金鑰'
      MSG_SSH_KEY_CREATE_WITH='找不到 SSH 金鑰 %s，使用 %s 建立中...'
      MSG_SSH_KEY_CREATE_FAILED='建立 SSH 金鑰 %s 失敗'
      MSG_SSH_HOST_KEY_REMOVE='正在移除 %s 的現有主機金鑰。'
      MSG_SSH_HOST_KEY_ADD='正在將 %s 加入已知主機。'
      MSG_SSH_PRIVATE_NOT_FOUND='找不到私鑰: %s'
      MSG_SSH_PUBLIC_NOT_FOUND='找不到公鑰: %s'
      MSG_SSH_KEY_INVALID='無效的私鑰: %s'
      MSG_SSH_KEY_MISMATCH='公鑰與私鑰不匹配。'
      MSG_SSH_COPY_FAILED='複製 SSH 金鑰到 %s 失敗。'
      MSG_SSH_RETRY_FAILED='SSH 重試 %d/%d 失敗: %s'
      MSG_SSH_FINAL_FAILURE='SSH 連線在 %d 次重試後失敗:'
      MSG_RSYNC_NOT_AVAILABLE='遠端主機上沒有 rsync，嘗試下一個工具...'
      MSG_NO_TRANSFER_TOOLS='沒有可用的檔案傳輸工具 (%s)。'
      MSG_NO_FILES_IN_RANGE='在時間範圍 %s ~ %s 中找不到檔案。'
      MSG_FILES_SELECTED='已選取 %d 個檔案（共 %d 個候選）。'
      MSG_USER_INPUTS_SUMMARY='使用者輸入摘要:'
      MSG_NO_SAVE_FOLDER='未定義 SAVE_FOLDER，略過清理。'
      MSG_FOLDER_REMOVE_FAILED='移除遠端資料夾失敗: %s'
      MSG_FOLDER_REMOVED='遠端資料夾 %s 已成功移除。'
      MSG_NO_FILES_TO_COPY='%s 沒有檔案可複製'
      MSG_COPY_FAILED='複製檔案到 %s 失敗'
      MSG_LOCAL_DESTINATION='本機目標資料夾: %s'
      MSG_REMOTE_NOT_FOUND='找不到遠端資料夾: %s'
      MSG_REMOTE_FOLDER_SIZE='遠端資料夾 %s 大小: %s'
      MSG_SIZE_EXCEED_CONFIRM='資料夾大小超過 %dMB（%s），確定要傳送嗎？[Y/n] '
      MSG_TRANSFER_CANCELLED='使用者取消傳送。'
      MSG_UNSUPPORTED_TOOL='不支援的檔案傳輸工具: %s'
      MSG_TRANSFER_RETRY='%s 失敗 (第 %d/%d 次)，%d 秒後重試...'
      MSG_TRANSFER_FAILED='%s 在 %d 次嘗試後失敗。'
      MSG_REMOTE_PRESERVED='遠端資料夾已保留: %s:%s'
      MSG_RETRIEVE_MANUALLY='請手動取回檔案，完成後請刪除遠端資料夾。'
      MSG_TRANSFER_CHOICE='[R]etry（重試，預設） / [K]eep（保留遠端資料） / [C]lean（清除遠端資料）: '
      MSG_EMPTY_PATH='[%d/%d] 解析後路徑為空，跳過。'
      MSG_NO_FILES_FOUND='[%d/%d] 找不到檔案。'
      MSG_DIR_NOT_FOUND='[%d/%d] 目錄不存在: %s'
      MSG_NO_PATTERN_MATCH='[%d/%d] 沒有符合樣式的檔案: %s'
      MSG_NO_TIME_MATCH='[%d/%d] 找到 %d 個檔案，但皆不在時間範圍 %s ~ %s 內'
      MSG_RESOLVED_PATH='[%d/%d] 解析結果: %s :: %s'
      MSG_FOUND_COPYING='[%d/%d] 找到 %d 個檔案，複製中...'
      MSG_STEP1='=== 步驟 1/6: 解析目標主機 ==='
      MSG_STEP2='=== 步驟 2/6: 驗證時間範圍 ==='
      MSG_STEP3_SSH='=== 步驟 3/6: 建立 SSH 連線 ==='
      MSG_STEP3_LOCAL='=== 步驟 3/6: 本機模式 (略過 SSH) ==='
      MSG_SUDO_REQUIRED='路徑 %s 不在 HOME 底下，需要 sudo 權限。'
      MSG_SUDO_FAILED='sudo 驗證失敗，路徑 %s 可能無法存取。'
      MSG_STEP4='=== 步驟 4/6: 收集 log 檔案 ==='
      MSG_STEP5_TRANSFER='=== 步驟 5/6: 傳輸檔案到本機 (%s) ==='
      MSG_STEP5_LOCAL='=== 步驟 5/6: 檔案已在本機收集完成 ==='
      MSG_STEP6_ARCHIVE='=== 步驟 6/6: 建立封存檔 ==='
      MSG_ARCHIVING='建立封存檔：%s'
      MSG_ARCHIVE_DONE='封存完成：%s (%s)'
      MSG_ARCHIVE_FAILED='建立封存檔失敗：%s'
      MSG_ARCHIVE_NO_FOLDER='無法封存：找不到資料夾：%s'
      MSG_ARCHIVE_CHOICE='選擇：[R] 重試 / [K] 僅保留資料夾 / [A] 中止：'
      MSG_ARCHIVE_KEEP_FOLDER='略過封存，資料夾保留於：%s'
      MSG_ARCHIVE_ABORTED='使用者中止封存，資料夾保留於：%s'
      MSG_WARN_DATE_STEP_UNSUPPORTED='%s 包含秒級 specifier，不支援秒級步進，回退為日級步進（可能漏掉目錄）'
      MSG_WARN_FILE_FINDER_BATCH_FAILED='批次時間戳解析失敗（%d 個時間戳），此範圍內所有候選檔案已跳過（可能漏檔）'
      MSG_OUTPUT_SECTION='=== 輸出 ==='
      MSG_OUTPUT_NAME='輸出資料夾：%s'
      MSG_OUTPUT_ARCHIVE='輸出封存檔：%s'
      MSG_SUCCESS='打包 log 完成。'
      MSG_SPINNER_SSH='正在連線至 %s...'
      MSG_SPINNER_TOKEN='正在解析路徑 token...'
      MSG_SPINNER_FINDING='[%d/%d] 正在搜尋檔案...'
      MSG_SPINNER_COPYING='[%d/%d] 正在複製 %d 個檔案...'
      MSG_SPINNER_SIZE='正在計算資料夾大小...'
      MSG_SPINNER_ARCHIVE='正在建立封存檔...'
      MSG_DRY_RUN_BANNER='*** 模擬執行模式 — 不會複製或傳輸任何檔案 ***'
      MSG_DRY_RUN_RESOLVED='[模擬] 解析後路徑：%s'
      MSG_DRY_RUN_PATTERN='[模擬] 檔案樣式：  %s'
      MSG_DRY_RUN_DIR_NOT_FOUND='[模擬] 目錄不存在：%s'
      MSG_DRY_RUN_WOULD_COPY='[模擬] 將會複製 %d 個檔案：'
      MSG_DRY_RUN_TOTAL='[模擬] 總共會收集的檔案數量：%d'
      MSG_DRY_RUN_COMPLETE='*** 模擬執行完成 — 未做任何變更 ***'
      MSG_DBG_CACHE_HIT='快取命中: %s = %s'
      MSG_DBG_EXECUTING_CMD='執行指令: %s'
      MSG_DBG_PREFETCH_BATCHING='prefetch_token_cache: 批次處理 %d 個 token'
      MSG_DBG_PREFETCH_FAILED='prefetch_token_cache: 批次失敗，退回逐一解析'
      MSG_DBG_PREFETCH_MISMATCH='prefetch_token_cache: 值數量不符 (%d vs %d)'
      MSG_DBG_PREFETCH_RESULT='prefetch_token_cache: %s = %s'
      MSG_DBG_NO_INPUT_PROMPTING='未提供編號或 user@host，提示輸入'
      MSG_DBG_USER_SELECTED_NUM='使用者選擇編號 %s'
      MSG_DBG_USER_PROVIDED_HOST='使用者提供 user@host %s'
      MSG_DBG_USE_NUM_FOR_HOST='使用編號 %s 取得主機'
      MSG_DBG_PARSED_SPECIAL='解析特殊字串 - 類型: %s, 字串: %s'
      MSG_DBG_RESOLVED_STRING='解析結果: %s'
      MSG_DBG_ORIGINAL_PATH='原始路徑: %s'
      MSG_DBG_ORIGINAL_PATTERN='原始樣式: %s'
      MSG_DBG_DATE_TOKEN_DEFERRED='日期 token 延後處理: %s'
      MSG_DBG_PROCESSING_TOKEN='處理 token: %s'
      MSG_DBG_EXPANDED_RANGE='展開範圍: %d 到 %d (值: %s ~ %s)'
      MSG_TRACE_INPUT='%s 輸入:'
      MSG_TRACE_OUTPUT='%s 輸出:'
      MSG_TRACE_PARAM='  %s: %s'
      MSG_TRACE_SINGLE_OUTPUT='%s 輸出: %s'
      MSG_RETRY_TRANSFER='正在重試傳輸...'
      MSG_RETRY_ARCHIVE='正在重試封存...'
      MSG_SUMMARY_HOST='主機: %s'
      MSG_SUMMARY_TIME_RANGE='時間範圍: %s ~ %s'
      MSG_SUMMARY_TOOL='傳輸工具: %s'
      MSG_SUMMARY_SAVE_FOLDER='儲存 log 至資料夾: %s'
      ;;
    zh-CN)
      MSG_HELP_USAGE='用法: %s [选项]'
      MSG_HELP_OPTIONS='  选项:'
      MSG_HELP_NUMBER='    -n, --number                  主机编号 (1-%d)'
      MSG_HELP_USERHOST='    -u, --userhost <user@host>    用户与主机 (例: user@host)'
      MSG_HELP_LOCAL='    -l, --local                   使用本机模式'
      MSG_HELP_START='    -s, --start <YYmmdd-HHMM>  起始时间 (例: 260101-0000)'
      MSG_HELP_END='    -e, --end <YYmmdd-HHMM>    结束时间 (例: 260101-2359)'
      MSG_HELP_OUTPUT='    -o, --output <路径>           输出文件夹路径（支持 <num>, <name>, <date:fmt>）'
      MSG_HELP_LANG='    --lang <代码>                 语言 (en, zh-TW, zh-CN, ja)'
      MSG_HELP_VERBOSE='    -v, --verbose                 启用详细输出'
      MSG_HELP_VERY_VERBOSE='    -vv, --very-verbose           启用更详细输出 (debug)'
      MSG_HELP_EXTRA_VERBOSE='    -vvv, --extra-verbose         启用最详细输出 (set -x)'
      MSG_HELP_DRY_RUN='    --dry-run                     模拟执行，不复制或传输文件'
      MSG_HELP_BWLIMIT='    --bwlimit <rate>              限制传输速度（默认 KB/s，支持 K/M/G[B] 后缀，0 = 不限制）'
      MSG_HELP_HELP='    -h, --help                    显示此帮助信息并退出'
      MSG_HELP_VERSION='    --version                     显示版本并退出'
      MSG_CHECKING_SUDO='正在检查 sudo 权限。'
      MSG_PKG_ALREADY_INSTALLED='软件包 %s 已安装。'
      MSG_PKG_NOT_FOUND='未找到软件包 %s，正在安装...'
      MSG_NO_SUDO_ACCESS='没有 sudo 权限来安装 %s。'
      MSG_PKG_INSTALL_FAILED='安装软件包 %s 失败。'
      MSG_INVALID_DATE_FORMAT='无效的日期格式: %s'
      MSG_DATE_FORMAT_FAILED='日期格式化失败: %s'
      MSG_UNKNOWN_TOKEN_TYPE='未知的类型: %s'
      MSG_COMMAND_FAILED='命令执行失败: %s'
      MSG_INVALID_SPECIAL_STRING='无效的特殊字符串格式: %s'
      MSG_UNKNOWN_SPECIAL_STRING='未知的特殊字符串类型: %s'
      MSG_TOKEN_NUM_NO_HOST='Token %s 需搭配 -n（主机编号），使用 -u 或 -l 时会被忽略'
      MSG_FOLDER_CREATE_FAILED='创建文件夹失败: %s'
      MSG_HOSTNAME_DATE_FAILED='无法从 %s 获取主机名/日期'
      MSG_HOST_USING_LOCAL='使用本机作为目标主机'
      MSG_HOST_PROMPT='输入 local、编号 (1-%d) 或 user@host: '
      MSG_INVALID_INPUT='无效的输入: %s'
      MSG_HOST_NUMBER_RANGE='编号必须在 1 到 %d 之间'
      MSG_INVALID_USERHOST='无效的 user@host 格式: %s'
      MSG_TIME_PROMPT='输入 %s (YYmmdd-HHMM): '
      MSG_INVALID_TIME_FORMAT='无效的 %s 格式: %s'
      MSG_START_BEFORE_END='起始时间 (%s) 必须早于结束时间 (%s)'
      MSG_SSH_ATTEMPT='正在尝试 SSH 连接到 %s (第 %d/%d 次)...'
      MSG_SSH_SUCCESS='SSH 连接到 %s 成功'
      MSG_SSH_KEY_EXISTS='SSH 密钥 %s 存在'
      MSG_SSH_PERMISSION_DENIED='SSH 密钥权限被拒，将尝试复制密钥。'
      MSG_SSH_HOST_CHANGED='SSH 主机标识已变更，正在移除旧密钥。'
      MSG_SSH_FAILED='SSH 连接失败: %s'
      MSG_SSH_KEY_NOT_FOUND='SSH 密钥 %s 不存在'
      MSG_SSH_KEY_CREATING='正在创建新的 SSH 密钥'
      MSG_SSH_KEY_CREATE_WITH='未找到 SSH 密钥 %s，使用 %s 创建中...'
      MSG_SSH_KEY_CREATE_FAILED='创建 SSH 密钥 %s 失败'
      MSG_SSH_HOST_KEY_REMOVE='正在移除 %s 的现有主机密钥。'
      MSG_SSH_HOST_KEY_ADD='正在将 %s 添加到已知主机。'
      MSG_SSH_PRIVATE_NOT_FOUND='未找到私钥: %s'
      MSG_SSH_PUBLIC_NOT_FOUND='未找到公钥: %s'
      MSG_SSH_KEY_INVALID='无效的私钥: %s'
      MSG_SSH_KEY_MISMATCH='公钥与私钥不匹配。'
      MSG_SSH_COPY_FAILED='复制 SSH 密钥到 %s 失败。'
      MSG_SSH_RETRY_FAILED='SSH 重试 %d/%d 失败: %s'
      MSG_SSH_FINAL_FAILURE='SSH 连接在 %d 次重试后失败:'
      MSG_RSYNC_NOT_AVAILABLE='远程主机上没有 rsync，尝试下一个工具...'
      MSG_NO_TRANSFER_TOOLS='没有可用的文件传输工具 (%s)。'
      MSG_NO_FILES_IN_RANGE='在时间范围 %s ~ %s 中未找到文件。'
      MSG_FILES_SELECTED='已选取 %d 个文件（共 %d 个候选）。'
      MSG_USER_INPUTS_SUMMARY='用户输入摘要:'
      MSG_NO_SAVE_FOLDER='未定义 SAVE_FOLDER，跳过清理。'
      MSG_FOLDER_REMOVE_FAILED='移除远程文件夹失败: %s'
      MSG_FOLDER_REMOVED='远程文件夹 %s 已成功移除。'
      MSG_NO_FILES_TO_COPY='%s 没有文件可复制'
      MSG_COPY_FAILED='复制文件到 %s 失败'
      MSG_LOCAL_DESTINATION='本机目标文件夹: %s'
      MSG_REMOTE_NOT_FOUND='未找到远程文件夹: %s'
      MSG_REMOTE_FOLDER_SIZE='远程文件夹 %s 大小: %s'
      MSG_SIZE_EXCEED_CONFIRM='文件夹大小超过 %dMB（%s），确定要传送吗？[Y/n] '
      MSG_TRANSFER_CANCELLED='用户取消传送。'
      MSG_UNSUPPORTED_TOOL='不支持的文件传输工具: %s'
      MSG_TRANSFER_RETRY='%s 失败 (第 %d/%d 次)，%d 秒后重试...'
      MSG_TRANSFER_FAILED='%s 在 %d 次尝试后失败。'
      MSG_REMOTE_PRESERVED='远程文件夹已保留: %s:%s'
      MSG_RETRIEVE_MANUALLY='请手动取回文件，完成后请删除远程文件夹。'
      MSG_TRANSFER_CHOICE='[R]etry（重试，默认） / [K]eep（保留远程数据） / [C]lean（清除远程数据）: '
      MSG_EMPTY_PATH='[%d/%d] 解析后路径为空，跳过。'
      MSG_NO_FILES_FOUND='[%d/%d] 未找到文件。'
      MSG_DIR_NOT_FOUND='[%d/%d] 目录不存在: %s'
      MSG_NO_PATTERN_MATCH='[%d/%d] 没有匹配模式的文件: %s'
      MSG_NO_TIME_MATCH='[%d/%d] 找到 %d 个文件，但均不在时间范围 %s ~ %s 内'
      MSG_RESOLVED_PATH='[%d/%d] 解析结果: %s :: %s'
      MSG_FOUND_COPYING='[%d/%d] 找到 %d 个文件，复制中...'
      MSG_STEP1='=== 步骤 1/6: 解析目标主机 ==='
      MSG_STEP2='=== 步骤 2/6: 验证时间范围 ==='
      MSG_STEP3_SSH='=== 步骤 3/6: 建立 SSH 连接 ==='
      MSG_STEP3_LOCAL='=== 步骤 3/6: 本机模式 (跳过 SSH) ==='
      MSG_SUDO_REQUIRED='路径 %s 不在 HOME 底下，需要 sudo 权限。'
      MSG_SUDO_FAILED='sudo 验证失败，路径 %s 可能无法访问。'
      MSG_STEP4='=== 步骤 4/6: 收集 log 文件 ==='
      MSG_STEP5_TRANSFER='=== 步骤 5/6: 传输文件到本机 (%s) ==='
      MSG_STEP5_LOCAL='=== 步骤 5/6: 文件已在本机收集完成 ==='
      MSG_STEP6_ARCHIVE='=== 步骤 6/6: 创建归档文件 ==='
      MSG_ARCHIVING='创建归档文件：%s'
      MSG_ARCHIVE_DONE='归档完成：%s (%s)'
      MSG_ARCHIVE_FAILED='创建归档文件失败：%s'
      MSG_ARCHIVE_NO_FOLDER='无法归档：找不到文件夹：%s'
      MSG_ARCHIVE_CHOICE='选择：[R] 重试 / [K] 仅保留文件夹 / [A] 中止：'
      MSG_ARCHIVE_KEEP_FOLDER='跳过归档，文件夹保留于：%s'
      MSG_ARCHIVE_ABORTED='用户中止归档，文件夹保留于：%s'
      MSG_WARN_DATE_STEP_UNSUPPORTED='%s 包含秒级 specifier，不支持秒级步进，回退为日级步进（可能漏掉目录）'
      MSG_WARN_FILE_FINDER_BATCH_FAILED='批次时间戳解析失败（%d 个时间戳），此范围内所有候选档案已跳过（可能漏档）'
      MSG_OUTPUT_SECTION='=== 输出 ==='
      MSG_OUTPUT_NAME='输出文件夹：%s'
      MSG_OUTPUT_ARCHIVE='输出归档：  %s'
      MSG_SUCCESS='打包 log 完成。'
      MSG_SPINNER_SSH='正在连接至 %s...'
      MSG_SPINNER_TOKEN='正在解析路径 token...'
      MSG_SPINNER_FINDING='[%d/%d] 正在搜索文件...'
      MSG_SPINNER_COPYING='[%d/%d] 正在复制 %d 个文件...'
      MSG_SPINNER_SIZE='正在计算文件夹大小...'
      MSG_SPINNER_ARCHIVE='正在创建归档文件...'
      MSG_DRY_RUN_BANNER='*** 模拟执行模式 — 不会复制或传输任何文件 ***'
      MSG_DRY_RUN_RESOLVED='[模拟] 解析后路径：%s'
      MSG_DRY_RUN_PATTERN='[模拟] 文件模式：  %s'
      MSG_DRY_RUN_DIR_NOT_FOUND='[模拟] 目录不存在：%s'
      MSG_DRY_RUN_WOULD_COPY='[模拟] 将会复制 %d 个文件：'
      MSG_DRY_RUN_TOTAL='[模拟] 总共会收集的文件数量：%d'
      MSG_DRY_RUN_COMPLETE='*** 模拟执行完成 — 未做任何变更 ***'
      MSG_DBG_CACHE_HIT='缓存命中: %s = %s'
      MSG_DBG_EXECUTING_CMD='执行命令: %s'
      MSG_DBG_PREFETCH_BATCHING='prefetch_token_cache: 批量处理 %d 个 token'
      MSG_DBG_PREFETCH_FAILED='prefetch_token_cache: 批量失败，回退到逐个解析'
      MSG_DBG_PREFETCH_MISMATCH='prefetch_token_cache: 值数量不匹配 (%d vs %d)'
      MSG_DBG_PREFETCH_RESULT='prefetch_token_cache: %s = %s'
      MSG_DBG_NO_INPUT_PROMPTING='未提供编号或 user@host，提示输入'
      MSG_DBG_USER_SELECTED_NUM='用户选择编号 %s'
      MSG_DBG_USER_PROVIDED_HOST='用户提供 user@host %s'
      MSG_DBG_USE_NUM_FOR_HOST='使用编号 %s 获取主机'
      MSG_DBG_PARSED_SPECIAL='解析特殊字符串 - 类型: %s, 字符串: %s'
      MSG_DBG_RESOLVED_STRING='解析结果: %s'
      MSG_DBG_ORIGINAL_PATH='原始路径: %s'
      MSG_DBG_ORIGINAL_PATTERN='原始模式: %s'
      MSG_DBG_DATE_TOKEN_DEFERRED='日期 token 延后处理: %s'
      MSG_DBG_PROCESSING_TOKEN='处理 token: %s'
      MSG_DBG_EXPANDED_RANGE='展开范围: %d 到 %d (值: %s ~ %s)'
      MSG_TRACE_INPUT='%s 输入:'
      MSG_TRACE_OUTPUT='%s 输出:'
      MSG_TRACE_PARAM='  %s: %s'
      MSG_TRACE_SINGLE_OUTPUT='%s 输出: %s'
      MSG_RETRY_TRANSFER='正在重试传输...'
      MSG_RETRY_ARCHIVE='正在重试归档...'
      MSG_SUMMARY_HOST='主机: %s'
      MSG_SUMMARY_TIME_RANGE='时间范围: %s ~ %s'
      MSG_SUMMARY_TOOL='传输工具: %s'
      MSG_SUMMARY_SAVE_FOLDER='保存日志到文件夹: %s'
      ;;
    ja)
      MSG_HELP_USAGE='使用法: %s [オプション]'
      MSG_HELP_OPTIONS='  オプション:'
      MSG_HELP_NUMBER='    -n, --number                  ホスト番号 (1-%d)'
      MSG_HELP_USERHOST='    -u, --userhost <user@host>    ユーザーとホスト (例: user@host)'
      MSG_HELP_LOCAL='    -l, --local                   ローカルモードを使用'
      MSG_HELP_START='    -s, --start <YYmmdd-HHMM>  開始時刻 (例: 260101-0000)'
      MSG_HELP_END='    -e, --end <YYmmdd-HHMM>    終了時刻 (例: 260101-2359)'
      MSG_HELP_OUTPUT='    -o, --output <パス>           出力フォルダパス（<num>, <name>, <date:fmt> 対応）'
      MSG_HELP_LANG='    --lang <コード>               言語 (en, zh-TW, zh-CN, ja)'
      MSG_HELP_VERBOSE='    -v, --verbose                 詳細出力を有効化'
      MSG_HELP_VERY_VERBOSE='    -vv, --very-verbose           より詳細な出力を有効化 (debug)'
      MSG_HELP_EXTRA_VERBOSE='    -vvv, --extra-verbose         最も詳細な出力を有効化 (set -x)'
      MSG_HELP_DRY_RUN='    --dry-run                     シミュレーション実行（ファイルのコピー・転送なし）'
      MSG_HELP_BWLIMIT='    --bwlimit <rate>              転送速度制限（デフォルト KB/s、K/M/G[B] 接尾辞対応、0 = 無制限）'
      MSG_HELP_HELP='    -h, --help                    このヘルプメッセージを表示して終了'
      MSG_HELP_VERSION='    --version                     バージョンを表示して終了'
      MSG_CHECKING_SUDO='sudo アクセスを確認中。'
      MSG_PKG_ALREADY_INSTALLED='パッケージ %s はインストール済みです。'
      MSG_PKG_NOT_FOUND='パッケージ %s が見つかりません。インストール中...'
      MSG_NO_SUDO_ACCESS='%s をインストールする sudo 権限がありません。'
      MSG_PKG_INSTALL_FAILED='パッケージ %s のインストールに失敗しました。'
      MSG_INVALID_DATE_FORMAT='無効な日付形式: %s'
      MSG_DATE_FORMAT_FAILED='日付のフォーマットに失敗: %s'
      MSG_UNKNOWN_TOKEN_TYPE='不明なタイプ: %s'
      MSG_COMMAND_FAILED='コマンド実行失敗: %s'
      MSG_INVALID_SPECIAL_STRING='無効な特殊文字列形式: %s'
      MSG_UNKNOWN_SPECIAL_STRING='不明な特殊文字列タイプ: %s'
      MSG_TOKEN_NUM_NO_HOST='トークン %s には -n（ホスト番号）が必要です。-u または -l 使用時は無視されます'
      MSG_FOLDER_CREATE_FAILED='フォルダの作成に失敗: %s'
      MSG_HOSTNAME_DATE_FAILED='%s からホスト名/日付を取得できません'
      MSG_HOST_USING_LOCAL='ローカルマシンをホストとして使用'
      MSG_HOST_PROMPT='local、番号 (1-%d)、または user@host を入力: '
      MSG_INVALID_INPUT='無効な入力: %s'
      MSG_HOST_NUMBER_RANGE='番号は 1 から %d の間で指定してください'
      MSG_INVALID_USERHOST='無効な user@host 形式: %s'
      MSG_TIME_PROMPT='%s を入力 (YYmmdd-HHMM): '
      MSG_INVALID_TIME_FORMAT='無効な %s 形式: %s'
      MSG_START_BEFORE_END='開始時刻 (%s) は終了時刻 (%s) より前でなければなりません'
      MSG_SSH_ATTEMPT='%s への SSH 接続を試行中 (第 %d/%d 回)...'
      MSG_SSH_SUCCESS='%s への SSH 接続成功'
      MSG_SSH_KEY_EXISTS='SSH キー %s が存在します'
      MSG_SSH_PERMISSION_DENIED='SSH キーの権限が拒否されました。キーのコピーを試みます。'
      MSG_SSH_HOST_CHANGED='SSH ホスト識別が変更されました。古いキーを削除中。'
      MSG_SSH_FAILED='SSH 接続失敗: %s'
      MSG_SSH_KEY_NOT_FOUND='SSH キー %s が存在しません'
      MSG_SSH_KEY_CREATING='新しい SSH キーを作成中'
      MSG_SSH_KEY_CREATE_WITH='SSH キー %s が見つかりません。%s で作成中...'
      MSG_SSH_KEY_CREATE_FAILED='SSH キー %s の作成に失敗'
      MSG_SSH_HOST_KEY_REMOVE='%s の既存ホストキーを削除中。'
      MSG_SSH_HOST_KEY_ADD='%s を既知のホストに追加中。'
      MSG_SSH_PRIVATE_NOT_FOUND='秘密鍵が見つかりません: %s'
      MSG_SSH_PUBLIC_NOT_FOUND='公開鍵が見つかりません: %s'
      MSG_SSH_KEY_INVALID='無効な秘密鍵: %s'
      MSG_SSH_KEY_MISMATCH='公開鍵と秘密鍵が一致しません。'
      MSG_SSH_COPY_FAILED='SSH キーの %s へのコピーに失敗。'
      MSG_SSH_RETRY_FAILED='SSH リトライ %d/%d 失敗: %s'
      MSG_SSH_FINAL_FAILURE='%d 回のリトライ後 SSH 接続に失敗:'
      MSG_RSYNC_NOT_AVAILABLE='リモートホストに rsync がありません。次のツールを試行中...'
      MSG_NO_TRANSFER_TOOLS='利用可能なファイル転送ツール (%s) がありません。'
      MSG_NO_FILES_IN_RANGE='時間範囲 %s ~ %s に該当するファイルが見つかりません。'
      MSG_FILES_SELECTED='%d 個のファイルを選択（候補 %d 個）。'
      MSG_USER_INPUTS_SUMMARY='ユーザー入力サマリー:'
      MSG_NO_SAVE_FOLDER='SAVE_FOLDER が未定義です。クリーンアップをスキップします。'
      MSG_FOLDER_REMOVE_FAILED='リモートフォルダの削除に失敗: %s'
      MSG_FOLDER_REMOVED='リモートフォルダ %s を正常に削除しました。'
      MSG_NO_FILES_TO_COPY='%s にコピーするファイルがありません'
      MSG_COPY_FAILED='%s へのファイルコピーに失敗'
      MSG_LOCAL_DESTINATION='ローカル保存先フォルダ: %s'
      MSG_REMOTE_NOT_FOUND='リモートフォルダが見つかりません: %s'
      MSG_REMOTE_FOLDER_SIZE='リモートフォルダ %s のサイズ: %s'
      MSG_SIZE_EXCEED_CONFIRM='フォルダサイズが %dMB（%s）を超えています。転送しますか？[Y/n] '
      MSG_TRANSFER_CANCELLED='転送がキャンセルされました。'
      MSG_UNSUPPORTED_TOOL='サポートされていないファイル転送ツール: %s'
      MSG_TRANSFER_RETRY='%s 失敗 (第 %d/%d 回)、%d 秒後にリトライ...'
      MSG_TRANSFER_FAILED='%s は %d 回の試行後に失敗しました。'
      MSG_REMOTE_PRESERVED='リモートフォルダを保持: %s:%s'
      MSG_RETRIEVE_MANUALLY='手動で取得し、完了後にリモートフォルダを削除してください。'
      MSG_TRANSFER_CHOICE='[R]etry（リトライ、デフォルト） / [K]eep（リモートデータ保持） / [C]lean（リモートデータ削除）: '
      MSG_EMPTY_PATH='[%d/%d] 解決済みパスが空です。スキップします。'
      MSG_NO_FILES_FOUND='[%d/%d] ファイルが見つかりません。'
      MSG_DIR_NOT_FOUND='[%d/%d] ディレクトリが存在しません: %s'
      MSG_NO_PATTERN_MATCH='[%d/%d] パターンに一致するファイルがありません: %s'
      MSG_NO_TIME_MATCH='[%d/%d] %d 個のファイルが見つかりましたが、時間範囲 %s ~ %s 内にありません'
      MSG_RESOLVED_PATH='[%d/%d] 解決済み: %s :: %s'
      MSG_FOUND_COPYING='[%d/%d] %d 個のファイルが見つかりました。コピー中...'
      MSG_STEP1='=== ステップ 1/6: ターゲットホストの解決 ==='
      MSG_STEP2='=== ステップ 2/6: 時間範囲の検証 ==='
      MSG_STEP3_SSH='=== ステップ 3/6: SSH 接続の確立 ==='
      MSG_STEP3_LOCAL='=== ステップ 3/6: ローカルモード (SSH スキップ) ==='
      MSG_SUDO_REQUIRED='パス %s は HOME 外のため、sudo 権限が必要です。'
      MSG_SUDO_FAILED='sudo 認証に失敗しました。パス %s にアクセスできない可能性があります。'
      MSG_STEP4='=== ステップ 4/6: ログファイルの収集 ==='
      MSG_STEP5_TRANSFER='=== ステップ 5/6: ローカルへファイル転送中 (%s) ==='
      MSG_STEP5_LOCAL='=== ステップ 5/6: ローカルでファイル収集完了 ==='
      MSG_STEP6_ARCHIVE='=== ステップ 6/6: アーカイブ作成中 ==='
      MSG_ARCHIVING='アーカイブ作成中：%s'
      MSG_ARCHIVE_DONE='アーカイブ作成完了：%s (%s)'
      MSG_ARCHIVE_FAILED='アーカイブの作成に失敗しました：%s'
      MSG_ARCHIVE_NO_FOLDER='アーカイブできません：フォルダが見つかりません：%s'
      MSG_ARCHIVE_CHOICE='選択：[R] 再試行 / [K] フォルダのみ保持 / [A] 中止：'
      MSG_ARCHIVE_KEEP_FOLDER='アーカイブをスキップしました。フォルダは保持されています：%s'
      MSG_ARCHIVE_ABORTED='ユーザーによってアーカイブが中止されました。フォルダは保持されています：%s'
      MSG_WARN_DATE_STEP_UNSUPPORTED='%s に秒単位の specifier が含まれます。秒単位ステップは未対応のため日単位にフォールバックします（ディレクトリを取りこぼす可能性あり）'
      MSG_WARN_FILE_FINDER_BATCH_FAILED='タイムスタンプの一括解析に失敗しました（%d 件）。この範囲内の候補ファイルはすべてスキップされます（ファイル漏れの可能性あり）'
      MSG_OUTPUT_SECTION='=== 出力 ==='
      MSG_OUTPUT_NAME='出力フォルダ：%s'
      MSG_OUTPUT_ARCHIVE='出力アーカイブ：%s'
      MSG_SUCCESS='ログのパッケージングが正常に完了しました。'
      MSG_SPINNER_SSH='%s に接続中...'
      MSG_SPINNER_TOKEN='パストークンを解決中...'
      MSG_SPINNER_FINDING='[%d/%d] ファイルを検索中...'
      MSG_SPINNER_COPYING='[%d/%d] %d ファイルをコピー中...'
      MSG_SPINNER_SIZE='フォルダサイズを計算中...'
      MSG_SPINNER_ARCHIVE='アーカイブを作成中...'
      MSG_DRY_RUN_BANNER='*** ドライランモード — ファイルのコピー・転送は行いません ***'
      MSG_DRY_RUN_RESOLVED='[ドライラン] 解決済みパス：%s'
      MSG_DRY_RUN_PATTERN='[ドライラン] ファイルパターン：%s'
      MSG_DRY_RUN_DIR_NOT_FOUND='[ドライラン] ディレクトリが見つかりません：%s'
      MSG_DRY_RUN_WOULD_COPY='[ドライラン] %d 個のファイルをコピー予定：'
      MSG_DRY_RUN_TOTAL='[ドライラン] 収集予定の合計ファイル数：%d'
      MSG_DRY_RUN_COMPLETE='*** ドライラン完了 — 変更は行われていません ***'
      MSG_DBG_CACHE_HIT='キャッシュヒット: %s = %s'
      MSG_DBG_EXECUTING_CMD='コマンド実行: %s'
      MSG_DBG_PREFETCH_BATCHING='prefetch_token_cache: %d 個のトークンをバッチ処理'
      MSG_DBG_PREFETCH_FAILED='prefetch_token_cache: バッチ失敗、個別解決にフォールバック'
      MSG_DBG_PREFETCH_MISMATCH='prefetch_token_cache: 値の数が不一致 (%d vs %d)'
      MSG_DBG_PREFETCH_RESULT='prefetch_token_cache: %s = %s'
      MSG_DBG_NO_INPUT_PROMPTING='番号または user@host が未指定、入力を要求'
      MSG_DBG_USER_SELECTED_NUM='ユーザーが番号 %s を選択'
      MSG_DBG_USER_PROVIDED_HOST='ユーザーが user@host %s を指定'
      MSG_DBG_USE_NUM_FOR_HOST='番号 %s でホストを取得'
      MSG_DBG_PARSED_SPECIAL='特殊文字列を解析 - タイプ: %s, 文字列: %s'
      MSG_DBG_RESOLVED_STRING='解決結果: %s'
      MSG_DBG_ORIGINAL_PATH='元のパス: %s'
      MSG_DBG_ORIGINAL_PATTERN='元のパターン: %s'
      MSG_DBG_DATE_TOKEN_DEFERRED='日付トークンを後で処理: %s'
      MSG_DBG_PROCESSING_TOKEN='トークン処理中: %s'
      MSG_DBG_EXPANDED_RANGE='展開範囲: %d から %d (値: %s ~ %s)'
      MSG_TRACE_INPUT='%s 入力:'
      MSG_TRACE_OUTPUT='%s 出力:'
      MSG_TRACE_PARAM='  %s: %s'
      MSG_TRACE_SINGLE_OUTPUT='%s 出力: %s'
      MSG_RETRY_TRANSFER='転送を再試行中...'
      MSG_RETRY_ARCHIVE='アーカイブを再試行中...'
      MSG_SUMMARY_HOST='ホスト: %s'
      MSG_SUMMARY_TIME_RANGE='時間範囲: %s ~ %s'
      MSG_SUMMARY_TOOL='転送ツール: %s'
      MSG_SUMMARY_SAVE_FOLDER='ログの保存先フォルダ: %s'
      ;;
    *) # English (default)
      MSG_HELP_USAGE='Usage: %s [options]'
      MSG_HELP_OPTIONS='  Options:'
      MSG_HELP_NUMBER='    -n, --number                  Host number (1-%d)'
      MSG_HELP_USERHOST='    -u, --userhost <user@host>    User and host (e.g. user@host)'
      MSG_HELP_LOCAL='    -l, --local                   Use local machine'
      MSG_HELP_START='    -s, --start <YYmmdd-HHMM>  Start time (e.g. 260101-0000)'
      MSG_HELP_END='    -e, --end <YYmmdd-HHMM>    End time (e.g. 260101-2359)'
      MSG_HELP_OUTPUT='    -o, --output <path>           Output folder path (supports <num>, <name>, <date:fmt>)'
      MSG_HELP_LANG='    --lang <code>                 Language (en, zh-TW, zh-CN, ja)'
      MSG_HELP_VERBOSE='    -v, --verbose                 Enable verbose output'
      MSG_HELP_VERY_VERBOSE='    -vv, --very-verbose           Enable very verbose output (debug)'
      MSG_HELP_EXTRA_VERBOSE='    -vvv, --extra-verbose         Enable extra verbose output (set -x)'
      MSG_HELP_DRY_RUN='    --dry-run                     Simulate without copying or transferring files'
      MSG_HELP_BWLIMIT='    --bwlimit <rate>              Limit transfer bandwidth (default KB/s; K/M/G[B] suffix supported, 0 = unlimited)'
      MSG_HELP_HELP='    -h, --help                    Show this help message and exit'
      MSG_HELP_VERSION='    --version                     Show version and exit'
      MSG_CHECKING_SUDO='Checking sudo access.'
      MSG_PKG_ALREADY_INSTALLED='Package %s already installed.'
      MSG_PKG_NOT_FOUND='Package %s not found, installing...'
      MSG_NO_SUDO_ACCESS='No sudo access to install %s.'
      MSG_PKG_INSTALL_FAILED='Failed to install package %s.'
      MSG_INVALID_DATE_FORMAT='Invalid date format: %s'
      MSG_DATE_FORMAT_FAILED='Failed to format date: %s'
      MSG_UNKNOWN_TOKEN_TYPE='Unknown type: %s'
      MSG_COMMAND_FAILED='Command failed: %s'
      MSG_INVALID_SPECIAL_STRING='Invalid special string format: %s'
      MSG_UNKNOWN_SPECIAL_STRING='Unknown special string type: %s'
      MSG_TOKEN_NUM_NO_HOST='Token %s requires -n (host number), ignored when using -u or -l'
      MSG_FOLDER_CREATE_FAILED='Failed to create folder: %s'
      MSG_HOSTNAME_DATE_FAILED='Failed to get hostname/date from %s'
      MSG_HOST_USING_LOCAL='Using local machine as host'
      MSG_HOST_PROMPT='Enter local, number (1-%d) or user@host: '
      MSG_INVALID_INPUT='Invalid input: %s'
      MSG_HOST_NUMBER_RANGE='Number must be between 1 and %d'
      MSG_INVALID_USERHOST='Invalid user@host format: %s'
      MSG_TIME_PROMPT='Enter %s (YYmmdd-HHMM): '
      MSG_INVALID_TIME_FORMAT='Invalid %s format: %s'
      MSG_START_BEFORE_END='start_time (%s) must be before end_time (%s)'
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
      MSG_RSYNC_NOT_AVAILABLE='rsync not available on remote host, trying next tool...'
      MSG_NO_TRANSFER_TOOLS='No file transfer tools (%s) available.'
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
      MSG_SIZE_EXCEED_CONFIRM='Folder size exceeds %dMB (%s). Proceed with transfer? [Y/n] '
      MSG_TRANSFER_CANCELLED='Transfer cancelled by user.'
      MSG_UNSUPPORTED_TOOL='Unsupported file transfer tool: %s'
      MSG_TRANSFER_RETRY='%s failed (attempt %d/%d), retrying in %ds...'
      MSG_TRANSFER_FAILED='%s failed after %d attempts.'
      MSG_REMOTE_PRESERVED='Remote folder preserved: %s:%s'
      MSG_RETRIEVE_MANUALLY='Please retrieve manually and delete when done.'
      MSG_TRANSFER_CHOICE='[R]etry (default) / [K]eep remote data / [C]lean remote data: '
      MSG_EMPTY_PATH='[%d/%d] Resolved path is empty, skipping.'
      MSG_NO_FILES_FOUND='[%d/%d] No files found.'
      MSG_DIR_NOT_FOUND='[%d/%d] Directory does not exist: %s'
      MSG_NO_PATTERN_MATCH='[%d/%d] No files matching pattern: %s'
      MSG_NO_TIME_MATCH='[%d/%d] Found %d files but none in time range %s ~ %s'
      MSG_RESOLVED_PATH='[%d/%d] Resolved: %s :: %s'
      MSG_FOUND_COPYING='[%d/%d] Found %d files, copying...'
      MSG_STEP1='=== Step 1/6: Resolving target host ==='
      MSG_STEP2='=== Step 2/6: Validating time range ==='
      MSG_STEP3_SSH='=== Step 3/6: Establishing SSH connection ==='
      MSG_STEP3_LOCAL='=== Step 3/6: Local mode (skipping SSH) ==='
      MSG_SUDO_REQUIRED='Path %s is outside HOME, sudo permission required.'
      MSG_SUDO_FAILED='sudo authentication failed, path %s may be inaccessible.'
      MSG_STEP4='=== Step 4/6: Collecting log files ==='
      MSG_STEP5_TRANSFER='=== Step 5/6: Transferring files to local (%s) ==='
      MSG_STEP5_LOCAL='=== Step 5/6: Files collected locally ==='
      MSG_STEP6_ARCHIVE='=== Step 6/6: Creating archive ==='
      MSG_ARCHIVING='Creating archive: %s'
      MSG_ARCHIVE_DONE='Archive created: %s (%s)'
      MSG_ARCHIVE_FAILED='Failed to create archive: %s'
      MSG_ARCHIVE_NO_FOLDER='Cannot archive: folder not found: %s'
      MSG_ARCHIVE_CHOICE='Choose: [R]etry / [K]eep folder only / [A]bort:'
      MSG_ARCHIVE_KEEP_FOLDER='Skipping archive, folder kept at: %s'
      MSG_ARCHIVE_ABORTED='Archive aborted by user, folder kept at: %s'
      MSG_WARN_DATE_STEP_UNSUPPORTED='%s contains a second-level specifier; second-level stepping is unsupported, falling back to day step (may miss directories)'
      MSG_WARN_FILE_FINDER_BATCH_FAILED='batch timestamp parse failed (%d timestamps); all candidate files in this range were skipped (possible missed files)'
      MSG_OUTPUT_SECTION='=== Output ==='
      MSG_OUTPUT_NAME='Output folder:  %s'
      MSG_OUTPUT_ARCHIVE='Output archive: %s'
      MSG_SUCCESS='Packaging log completed successfully.'
      MSG_SPINNER_SSH='Connecting to %s...'
      MSG_SPINNER_TOKEN='Resolving path tokens...'
      MSG_SPINNER_FINDING='[%d/%d] Searching for files...'
      MSG_SPINNER_COPYING='[%d/%d] Copying %d files...'
      MSG_SPINNER_SIZE='Calculating folder size...'
      MSG_SPINNER_ARCHIVE='Creating archive...'
      MSG_DRY_RUN_BANNER='*** DRY RUN MODE — no files will be copied or transferred ***'
      MSG_DRY_RUN_RESOLVED='[dry-run] Resolved path: %s'
      MSG_DRY_RUN_PATTERN='[dry-run] File pattern:  %s'
      MSG_DRY_RUN_DIR_NOT_FOUND='[dry-run] Directory not found: %s'
      MSG_DRY_RUN_WOULD_COPY='[dry-run] Would copy %d files:'
      MSG_DRY_RUN_TOTAL='[dry-run] Total files that would be collected: %d'
      MSG_DRY_RUN_COMPLETE='*** Dry run complete — no changes were made ***'
      MSG_DBG_CACHE_HIT='Cache hit: %s = %s'
      MSG_DBG_EXECUTING_CMD='Executing command: %s'
      MSG_DBG_PREFETCH_BATCHING='prefetch_token_cache: batching %d token(s)'
      MSG_DBG_PREFETCH_FAILED='prefetch_token_cache: batch failed, falling back'
      MSG_DBG_PREFETCH_MISMATCH='prefetch_token_cache: value count mismatch (%d vs %d)'
      MSG_DBG_PREFETCH_RESULT='prefetch_token_cache: %s = %s'
      MSG_DBG_NO_INPUT_PROMPTING='No number or user@host provided, prompting'
      MSG_DBG_USER_SELECTED_NUM='User selected number %s'
      MSG_DBG_USER_PROVIDED_HOST='User provided user@host %s'
      MSG_DBG_USE_NUM_FOR_HOST='Use number %s to get host'
      MSG_DBG_PARSED_SPECIAL='Parsed special string - type: %s, string: %s'
      MSG_DBG_RESOLVED_STRING='Resolved string: %s'
      MSG_DBG_ORIGINAL_PATH='Original path: %s'
      MSG_DBG_ORIGINAL_PATTERN='Original pattern: %s'
      MSG_DBG_DATE_TOKEN_DEFERRED='Date token deferred: %s'
      MSG_DBG_PROCESSING_TOKEN='Processing token: %s'
      MSG_DBG_EXPANDED_RANGE='Expanded range: %d to %d (Values: %s ~ %s)'
      MSG_TRACE_INPUT='%s input:'
      MSG_TRACE_OUTPUT='%s output:'
      MSG_TRACE_PARAM='  %s: %s'
      MSG_TRACE_SINGLE_OUTPUT='%s output: %s'
      MSG_RETRY_TRANSFER='Retrying transfer...'
      MSG_RETRY_ARCHIVE='Retrying archive...'
      MSG_SUMMARY_HOST='Host: %s'
      MSG_SUMMARY_TIME_RANGE='Time range: %s ~ %s'
      MSG_SUMMARY_TOOL='Using tool: %s'
      MSG_SUMMARY_SAVE_FOLDER='Saving logs to folder: %s'
      ;;
  esac
}

# Load default (English) messages on source so log functions work before
# option_parser/main runs. LANG_CODE is intentionally left empty here so that
# auto-detection from $LANG can fire later in main()/option_parser.
load_lang

# --- Log functions ---
# Color codes (disabled when stdout/stderr is not a terminal)
if [[ -t 2 ]]; then
  _C_RESET='\033[0m'
  _C_RED='\033[1;31m'
  _C_YELLOW='\033[1;33m'
  _C_GREEN='\033[0;32m'
  _C_CYAN='\033[0;36m'
  _C_DIM='\033[2m'
else
  _C_RESET='' _C_RED='' _C_YELLOW='' _C_GREEN='' _C_CYAN='' _C_DIM=''
fi

# Writes plain-text log entry to the log file (no-op if log file not yet initialized).
#
# Globals:
#   _LOG_FD  Read; file descriptor opened by init_log_file.
# Arguments:
#   $@  Message to write.
# Outputs:
#   Writes one line to the log file via _LOG_FD.
# Returns:
#   0 always.
_log_to_file() {
  [[ -n "${_LOG_FD}" ]] && printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%:z')" "$*" >&"${_LOG_FD}"
  return 0
}

# Opens the log file for writing. Call after SAVE_FOLDER is finalized.
# In remote mode, SAVE_FOLDER exists on the remote host but not locally.
# Create the local directory first so the log file can be written.
#
# Globals:
#   SAVE_FOLDER  Read; destination directory.
#   LOG_FILE     Written; absolute path of the log file.
#   _LOG_FD      Written; file descriptor opened for append.
# Arguments:
#   None.
# Outputs:
#   None (creates directory and opens fd).
# Returns:
#   0 on success; non-zero if mkdir/exec fails (set -e aborts).
init_log_file() {
  LOG_FILE="${SAVE_FOLDER}/pack_log.log"
  mkdir -p "${SAVE_FOLDER}"
  exec {_LOG_FD}>>"${LOG_FILE}"
}

# Closes the log file descriptor. Safe to call multiple times.
#
# Globals:
#   _LOG_FD  Read/written; cleared after close.
# Arguments:
#   None.
# Outputs:
#   None.
# Returns:
#   0 always.
close_log_file() {
  if [[ -n "${_LOG_FD}" ]]; then
    exec {_LOG_FD}>&-
    _LOG_FD=""
  fi
}

# --- Spinner (liveness indicator) ---
# Shows a rotating character on stderr during long-running operations so the
# user can tell the script hasn't hung. Non-interactive (non-tty) environments
# print the message once and skip the animation to keep logs clean.
declare _SPINNER_PID=""
declare _SPINNER_FRAMES='\|/-'

# Reports whether stderr is attached to a terminal. Extracted as a function
# so tests can override it without relying on an actual tty.
#
# Globals:
#   None.
# Arguments:
#   None.
# Outputs:
#   None.
# Returns:
#   0 if stderr is a tty; 1 otherwise.
_spinner_is_tty() {
  [[ -t 2 ]]
}

# Starts the spinner. Stops any previously running spinner first so repeated
# calls don't leak background processes.
#
# Globals:
#   _SPINNER_PID     Written; PID of the background animation process.
#   _SPINNER_FRAMES  Read; frame characters to cycle through.
# Arguments:
#   $1  Message to display alongside the spinner.
# Outputs:
#   Animated frame + message on stderr (tty path), or a single message line
#   (non-tty path).
# Returns:
#   0 always.
spinner_start() {
  local msg="$1"
  spinner_stop
  if ! _spinner_is_tty; then
    printf '%s\n' "${msg}" >&2
    return 0
  fi
  (
    local i=0
    local frames_len="${#_SPINNER_FRAMES}"
    while true; do
      printf '\r%s %s' "${_SPINNER_FRAMES:i++%frames_len:1}" "${msg}" >&2
      sleep 0.15
    done
  ) &
  _SPINNER_PID=$!
}

# Stops the spinner and clears the current line. Safe to call when no spinner
# is running or to call multiple times.
#
# Globals:
#   _SPINNER_PID  Read/written; cleared after the background process is reaped.
# Arguments:
#   None.
# Outputs:
#   ANSI erase sequence on stderr (tty path only).
# Returns:
#   0 always.
spinner_stop() {
  if [[ -n "${_SPINNER_PID}" ]]; then
    kill "${_SPINNER_PID}" 2>/dev/null || true
    wait "${_SPINNER_PID}" 2>/dev/null || true
    _SPINNER_PID=""
    printf '\r\033[K' >&2
  fi
}

log_verbose() { [[ "${VERBOSE:-0}" -ge 2 ]] && printf "${_C_DIM}%s${_C_RESET}\n" "$*" >&2; _log_to_file "[VERBOSE] $*"; return 0; }
log_debug()   { [[ "${VERBOSE:-0}" -ge 1 ]] && printf "${_C_CYAN}[DEBUG]${_C_RESET} %s\n" "$*" >&2; _log_to_file "[DEBUG] $*"; return 0; }
log_info()    { spinner_stop; printf "${_C_GREEN}[INFO]${_C_RESET}  %s\n" "$*"; _log_to_file "[INFO]  $*"; }
log_warn()    { spinner_stop; printf "${_C_YELLOW}[WARN]${_C_RESET}  %s\n" "$*" >&2; _log_to_file "[WARN]  $*"; }
log_error()   { spinner_stop; printf "${_C_RED}[ERROR]${_C_RESET} %s\n" "$*" >&2; _log_to_file "[ERROR] $*"; close_log_file; exit 1; }

# Prints the help message for the script.
#
# Globals:
#   HOSTS         Read; size used to render number-selection range.
#   MSG_HELP_*    Read; localized help strings.
# Arguments:
#   None.
# Outputs:
#   Writes the localized help text to stdout.
# Returns:
#   0 always.
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
  echo "${MSG_HELP_DRY_RUN}"
  echo "${MSG_HELP_BWLIMIT}"
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
# Globals:
#   HAVE_SUDO_ACCESS  Read/written; cached result (0/1) across calls.
#   SUDO_ASKPASS      Read; if set, sudo is invoked with -A.
#   EUID, UID         Read; root short-circuit.
# Arguments:
#   None.
# Outputs:
#   Writes MSG_CHECKING_SUDO to log on first invocation.
# Returns:
#   0 if the user has sudo access or is root.
#   1 otherwise.
have_sudo_access() {
  local sudo_bin
  sudo_bin="$(command -v sudo 2>/dev/null || true)"
  local -a sudo_cmd=("${sudo_bin}")

  # check if already root
  if [[ "${EUID:-${UID}}" -eq 0 ]]; then
    return 0
  fi

  # check sudo executable exists and is executable
  if [[ -z "${sudo_bin}" || ! -x "${sudo_bin}" ]]; then
    return 1
  fi

  # processing SUDO_ASKPASS
  if [[ -n "${SUDO_ASKPASS-}" ]]; then
    sudo_cmd+=("-A")
  fi

  # check sudo access only once
  if [[ -z "${HAVE_SUDO_ACCESS-}" ]]; then
    log_info "${MSG_CHECKING_SUDO}"
    if "${sudo_cmd[@]}" -v && "${sudo_cmd[@]}" -l mkdir &>/dev/null; then
      HAVE_SUDO_ACCESS=0
    else
      HAVE_SUDO_ACCESS=1
    fi
  fi

  return "${HAVE_SUDO_ACCESS}"
}

# Installs a package using apt-get if it is not already installed.
#
# Globals:
#   MSG_PKG_ALREADY_INSTALLED, MSG_PKG_NOT_FOUND, MSG_NO_SUDO_ACCESS,
#   MSG_PKG_INSTALL_FAILED                Read; localized log strings.
# Arguments:
#   pkg_name: The name of the package to install.
# Outputs:
#   Verbose / info / warn log lines; sudo apt-get output on stdout/stderr.
# Returns:
#   0 if installed (or already present); 1 if sudo unavailable or install failed.
pkg_install_handler() {
  local -r pkg_name="$1"

  log_verbose "$(printf "${MSG_TRACE_INPUT}" "${FUNCNAME[0]}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "pkg_name" "${pkg_name}")"

  # Check if the package is already installed.
  if command -v "${pkg_name}" >/dev/null 2>&1; then
    log_debug "$(printf "${MSG_PKG_ALREADY_INSTALLED}" "${pkg_name}")"
    return 0
  fi

  log_info "$(printf "${MSG_PKG_NOT_FOUND}" "${pkg_name}")"

  # Check for sudo access. If missing, return error so caller can decide.
  if ! have_sudo_access; then
    log_warn "$(printf "${MSG_NO_SUDO_ACCESS}" "${pkg_name}")"
    return 1
  fi

  # Attempt to update and install the package.
  # We separate the logic to ensure 'return 1' only runs on failure.
  if ! { sudo apt-get update && sudo apt-get install -y "${pkg_name}"; }; then
    log_warn "$(printf "${MSG_PKG_INSTALL_FAILED}" "${pkg_name}")"
    return 1
  fi

  log_verbose "--------------------"
}

# Converts a date string (YYYYmmdd-HHMMSS) to the given strftime format.
#
# Arguments:
#   date:   The date string in YYYYmmdd-HHMMSS format.
#   format: The strftime format to convert to (e.g. %Y%m%d%H%M%S, %s).
#
# Globals:
#   REPLY                       Written; the formatted date string.
#   MSG_INVALID_DATE_FORMAT,
#   MSG_DATE_FORMAT_FAILED      Read; localized error messages.
# Outputs:
#   Verbose log lines on stderr; fatal log_error on parse failure.
# Returns:
#   0 on success; aborts via log_error on failure.
date_format() {
  local -r date="${1:?"${FUNCNAME[0]} need date."}"; shift
  local -r format="${1:?"${FUNCNAME[0]} need format."}"; shift

  log_verbose "$(printf "${MSG_TRACE_INPUT}" "${FUNCNAME[0]}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "date" "${date}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "format" "${format}")"

  if [[ ! "${date}" =~ ^[0-9]{6}-[0-9]{4}$ ]]; then
    log_error "$(printf "${MSG_INVALID_DATE_FORMAT}" "${date}")"
  fi

  local ymd hms
  ymd="20${date:0:2}-${date:2:2}-${date:4:2}"
  hms="${date:7:2}:${date:9:2}:00"

  if ! REPLY=$(date -d "${ymd} ${hms}" "+${format}"); then
    log_error "$(printf "${MSG_DATE_FORMAT_FAILED}" "${date}")"
  fi

  log_verbose "$(printf "${MSG_TRACE_SINGLE_OUTPUT}" "${FUNCNAME[0]}" "${REPLY}")"
  log_verbose "--------------------"
}

# Executes a shell command locally or on a remote host via SSH.
#
# Pipes the command string into 'bash -ls' via stdin, bypassing complex
# shell escaping and nested quoting issues.
#
# Globals:
#   HOST       Read; "local" runs in local bash, otherwise SSH target.
#   SSH_OPTS   Read; SSH options array.
#   SSH_KEY,
#   SSH_TIMEOUT Read; logged for verbose tracing.
# Arguments:
#   inner_cmd: The shell command string to execute.
# Outputs:
#   Forwards stdout/stderr from the executed command.
# Returns:
#   The exit status of the executed command.
execute_cmd() {
  local -r inner_cmd="${1:?"${FUNCNAME[0]} need inner command."}"; shift
  local ret=0

  log_verbose "$(printf "${MSG_TRACE_INPUT}" "${FUNCNAME[0]}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "inner_cmd" "${inner_cmd}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "HOST" "${HOST}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "SSH_KEY" "${SSH_KEY}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "SSH_TIMEOUT" "${SSH_TIMEOUT}")"

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
# Globals:
#   _TOKEN_CACHE  Read/written; cache of resolved tokens to skip repeated SSH.
#   HOST          Read; "local" short-circuits env lookups.
#   REPLY         Written; the resolved value.
#   MSG_UNKNOWN_TOKEN_TYPE,
#   MSG_COMMAND_FAILED  Read; localized error messages.
# Outputs:
#   Verbose/debug log lines; fatal log_error on unknown type or command failure.
# Returns:
#   0 on success; aborts via log_error on failure.
get_remote_value() {
  local -r type="${1:?"${FUNCNAME[0]} need type."}"; shift
  local -r str="${1:?"${FUNCNAME[0]} need string."}"; shift

  log_verbose "$(printf "${MSG_TRACE_INPUT}" "${FUNCNAME[0]}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "type" "${type}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "str" "${str}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "HOST" "${HOST}")"

  # Check cache first to avoid redundant SSH calls
  local cache_key="${type}:${str}"
  if [[ -n "${_TOKEN_CACHE["${cache_key}"]+set}" ]]; then
    REPLY="${_TOKEN_CACHE["${cache_key}"]}"
    log_debug "$(printf "${MSG_DBG_CACHE_HIT}" "${cache_key}" "${REPLY}")"
    return 0
  fi

  if [[ "${HOST}" == "local" && "${type}" == "env" ]]; then
    REPLY="${!str}"
    _TOKEN_CACHE["${cache_key}"]="${REPLY}"
    return 0
  fi

  local get_cmd=""
  if [[ "${type}" == "env" ]]; then
    printf -v get_cmd 'printf "%%s" "${%s}"' "${str}"
  elif [[ "${type}" == "cmd" ]]; then
    get_cmd="${str}"
  else
    log_error "$(printf "${MSG_UNKNOWN_TOKEN_TYPE}" "${type}")"
  fi

  log_debug "$(printf "${MSG_DBG_EXECUTING_CMD}" "${get_cmd}")"

  if ! REPLY=$(execute_cmd "${get_cmd}"); then
    log_error "$(printf "${MSG_COMMAND_FAILED}" "${get_cmd}")"
  fi
  _TOKEN_CACHE["${cache_key}"]="${REPLY}"

  log_verbose "--------------------"
}

# Pre-populates _TOKEN_CACHE with every unique <env:VAR> and <cmd:...> token
# referenced in LOG_PATHS, using a single execute_cmd round-trip.
#
# Without this, get_remote_value resolves each unique token lazily on first
# use — N unique tokens means N sequential SSH round-trips. On a slow link
# that's a noticeable startup pause. Batching collapses them to one.
#
# Strategy: scan LOG_PATHS for tokens, build one shell script that prints
# each value followed by a runtime-generated sentinel, run it once, split
# the output, and stuff the results into _TOKEN_CACHE. Tokens already in
# the cache are skipped. Any failure (batch script error, value count
# mismatch) silently falls back to the lazy path in get_remote_value, so
# this is strictly a best-effort optimization.
#
# Globals:
#   LOG_PATHS     Read; scanned for <env:>/<cmd:> tokens.
#   _TOKEN_CACHE  Read/written; populated with resolved values.
# Arguments:
#   None.
# Outputs:
#   Debug traces only; never aborts on failure.
# Returns:
#   0 always.
prefetch_token_cache() {
  local -A unique=()
  local i s rest tok_type tok_val
  local token_pat='<(env|cmd):([^<>]+)>'
  for (( i=0; i<${#LOG_PATHS[@]}; i+=3 )); do
    for s in "${LOG_PATHS[i]}" "${LOG_PATHS[i+1]}"; do
      rest="${s}"
      while [[ "${rest}" =~ $token_pat ]]; do
        tok_type="${BASH_REMATCH[1]}"
        tok_val="${BASH_REMATCH[2]}"
        unique["${tok_type}:${tok_val}"]=1
        rest="${rest/"${BASH_REMATCH[0]}"/}"
      done
    done
  done

  local -a missing=()
  local key
  for key in "${!unique[@]}"; do
    [[ -n "${_TOKEN_CACHE[${key}]+set}" ]] && continue
    missing+=("${key}")
  done
  (( ${#missing[@]} == 0 )) && return 0

  local sep="__PACK_LOG_TOK_SEP_$$_${RANDOM}_${RANDOM}__"
  local script="" part=""
  for key in "${missing[@]}"; do
    tok_type="${key%%:*}"
    tok_val="${key#*:}"
    if [[ "${tok_type}" == "env" ]]; then
      printf -v part 'printf "%%s%s" "${%s}"; ' "${sep}" "${tok_val}"
    else
      printf -v part 'printf "%%s%s" "$(%s)"; ' "${sep}" "${tok_val}"
    fi
    script+="${part}"
  done

  log_debug "$(printf "${MSG_DBG_PREFETCH_BATCHING}" "${#missing[@]}")"
  local result
  if ! result=$(execute_cmd "${script}"); then
    log_debug "${MSG_DBG_PREFETCH_FAILED}"
    return 0
  fi

  local -a values=()
  local rest_out="${result}"
  while [[ "${rest_out}" == *"${sep}"* ]]; do
    values+=("${rest_out%%"${sep}"*}")
    rest_out="${rest_out#*"${sep}"}"
  done

  if (( ${#values[@]} != ${#missing[@]} )); then
    log_debug "$(printf "${MSG_DBG_PREFETCH_MISMATCH}" "${#values[@]}" "${#missing[@]}")"
    return 0
  fi

  local idx=0
  for key in "${missing[@]}"; do
    _TOKEN_CACHE["${key}"]="${values[idx]}"
    log_debug "$(printf "${MSG_DBG_PREFETCH_RESULT}" "${key}" "${values[idx]}")"
    (( ++idx ))
  done
  return 0
}

# Checks if a path requires sudo to access.
# Returns 0 (true) if sudo is needed, 1 (false) otherwise.
#
# Sudo is needed when:
#   - The <sudo> flag is explicitly set, OR
#   - The resolved path is NOT under the user's HOME directory
#
# Arguments:
#   path:  The resolved file path to check.
#   flags: The FLAGS column from LOG_PATHS (may contain "<sudo>").
#
# Globals:
#   HOST  Read; "local" uses ${HOME}, remote queries via execute_cmd.
#   HOME  Read in local mode.
# Outputs:
#   None on success; remote HOME query may emit verbose logs via execute_cmd.
# Returns:
#   0 if sudo is required; 1 otherwise.
_needs_sudo() {
  local path="${1:-}" flags="${2:-}"

  # Explicit <sudo> flag always triggers sudo
  [[ "${flags}" == *"<sudo>"* ]] && return 0

  # Determine HOME directory (local or remote)
  local home_dir
  if [[ "${HOST}" == "local" ]]; then
    home_dir="${HOME}"
  else
    home_dir=$(execute_cmd 'printf "%s" "${HOME}"') || return 1
  fi

  # Public directories don't need sudo
  [[ "${path}" == /tmp/* ]] && return 1

  # Path outside HOME → needs sudo
  [[ "${path}" != "${home_dir}/"* && "${path}" != "${home_dir}" ]] && return 0

  return 1
}

# Creates a folder on the local or remote machine.
#
# Globals:
#   HOST                       Read via execute_cmd; local or remote target.
#   MSG_FOLDER_CREATE_FAILED   Read; localized error message.
# Arguments:
#   path: The path of the folder to create.
# Outputs:
#   Verbose log lines; fatal log_error on failure.
# Returns:
#   0 on success; aborts via log_error on failure.
create_folder() {
  local -r path="${1:?"${FUNCNAME[0]} need path."}"; shift

  log_verbose "$(printf "${MSG_TRACE_INPUT}" "${FUNCNAME[0]}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "path" "${path}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "HOST" "${HOST}")"

  local mkdir_cmd
  printf -v mkdir_cmd "mkdir -p %q" "${path}"
  readonly mkdir_cmd

  if ! execute_cmd "${mkdir_cmd}"; then
    log_error "$(printf "${MSG_FOLDER_CREATE_FAILED}" "${path}")"
  fi

  log_verbose "--------------------"
}

# Executes a command using an array of strings as null-delimited stdin.
#
# Globals:
#   HOST      Read; "local" uses local eval, otherwise piped over SSH.
#   SSH_OPTS  Read; SSH options array.
# Arguments:
#   inner_cmd: The command to execute (e.g., "xargs ...").
#   ...:       Array elements to pipe as null-delimited stdin.
# Outputs:
#   Forwards stdout/stderr from the executed command.
# Returns:
#   The exit status of the executed command.
execute_cmd_from_array() {
  local -r inner_cmd="${1:?"${FUNCNAME[0]} need inner command."}"; shift
  local ret=0

  log_verbose "$(printf "${MSG_TRACE_INPUT}" "${FUNCNAME[0]}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "inner_cmd" "${inner_cmd}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "array size" "$# elements")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "HOST" "${HOST}")"

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

# Parses a bandwidth value with optional K/M/G[B] suffix into KB/s.
#
# Accepts a plain non-negative integer ("500"), or a value followed by an
# IEC-style suffix: K/KB (x1), M/MB (x1024), G/GB (x1048576). Case-insensitive.
# The trailing "B" is optional to match the rsync convention of "K/M/G".
#
# Globals:
#   None.
# Arguments:
#   $1: Raw input string (e.g. "500", "10M", "1GB", "500kb").
# Outputs:
#   KB/s as a non-negative integer on stdout (success path).
# Returns:
#   0 on success; 1 if the input is empty, non-numeric, negative,
#   or uses an unsupported suffix (e.g. "10T").
_parse_bwlimit() {
  local input="${1^^}"
  local num unit multiplier

  if [[ ! "${input}" =~ ^([0-9]+)(K|KB|M|MB|G|GB)?$ ]]; then
    return 1
  fi
  num="${BASH_REMATCH[1]}"
  unit="${BASH_REMATCH[2]}"

  case "${unit}" in
    ''|K|KB) multiplier=1 ;;
    M|MB)    multiplier=1024 ;;
    G|GB)    multiplier=1048576 ;;
  esac

  printf '%d\n' $(( num * multiplier ))
}

# Parses the command-line options.
#
# This function uses `getopt` to parse the command-line options and set the
# corresponding variables.
#
# Globals:
#   NUM, HOST, START_TIME, END_TIME, SAVE_FOLDER, VERBOSE, DRY_RUN,
#   LANG_CODE, VERSION  Written/Read; populated from matching CLI options.
# Arguments:
#   $@: The command-line options.
# Outputs:
#   Writes help/version text to stdout; warnings to stderr. Enables xtrace
#   when verbosity reaches 3.
# Returns:
#   0 on success; exits 0 after --help/--version, exits 1 on parse failure.
option_parser() {
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
    "dry-run"
    "bwlimit:"
    "help" "version"
  )

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
        VERBOSE=3; shift ;;
      --dry-run)
        DRY_RUN=true; shift ;;
      --bwlimit)
        local _bw_parsed
        if _bw_parsed=$(_parse_bwlimit "$2"); then
          BANDWIDTH_LIMIT="${_bw_parsed}"
        else
          echo "[ERROR] --bwlimit requires a non-negative integer, optionally with K/M/G[B] suffix (e.g. 500, 10M, 1GB), got: '$2'" >&2
          exit 1
        fi
        shift 2 ;;
      --lang)
        case "$2" in
          en|zh-TW|zh-CN|ja) LANG_CODE="$2" ;;
          *) echo "[WARN]  Unknown language '$2', supported: en, zh-TW, zh-CN, ja. Falling back to en." >&2
             LANG_CODE="en" ;;
        esac
        shift 2 ;;
      -h | --help)
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
      *) break ;;
    esac
  done

  if [[ "${VERBOSE:-0}" -ge 3 ]]; then
    set -x
  fi
}

# Handles the host selection.
#
# This function determines which host to connect to based on the user's input.
# It can be a number from the `HOSTS` array, a `user@host` string, or "local".
# If no host is provided, it prompts the user to select one.
#
# Globals:
#   HOSTS      Read; list of configured display_name::user@host entries.
#   NUM        Read/Written; host index (1-based) into HOSTS.
#   HOST       Read/Written; resolved user@host string or "local".
#   MSG_HOST_* Read; localized prompts and error messages.
# Arguments:
#   None.
# Outputs:
#   Prints the selection menu and prompt to stdout; debug/verbose traces.
# Returns:
#   0 on success; aborts via log_error on invalid input or out-of-range number.
host_handler() {
  log_verbose "$(printf "${MSG_TRACE_INPUT}" "${FUNCNAME[0]}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "NUM" "${NUM}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "HOST" "${HOST}")"

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
    log_debug "${MSG_DBG_NO_INPUT_PROMPTING}"
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
      log_debug "$(printf "${MSG_DBG_USER_SELECTED_NUM}" "${input}")"
      NUM="${input}"
      HOST=""
    elif [[ "${input}" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]]; then
      log_debug "$(printf "${MSG_DBG_USER_PROVIDED_HOST}" "${input}")"
      HOST="${input}"
      NUM=""
    else
      log_error "$(printf "${MSG_INVALID_INPUT}" "${input}")"
    fi
  fi

  # check number
  if [[ "${NUM}" =~ ^[1-9][0-9]*$ ]]; then
    if (( "${NUM}" < 1 || "${NUM}" > ${#HOSTS[@]} )); then
      log_error "$(printf "${MSG_HOST_NUMBER_RANGE}" "${#HOSTS[@]}")"
    fi

    log_debug "$(printf "${MSG_DBG_USE_NUM_FOR_HOST}" "${NUM}")"
    HOST="${HOSTS[${NUM}-1]#*::}"
  fi

  # check user@host format
  if [[ ! "${HOST}" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]]; then
    log_error "$(printf "${MSG_INVALID_USERHOST}" "${HOST}")"
  fi

  log_verbose "$(printf "${MSG_TRACE_OUTPUT}" "${FUNCNAME[0]}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "HOST" "${HOST}")"
  log_verbose "--------------------"
}

# Handles the time range selection.
#
# This function prompts the user to enter the start and end times for the log
# search if they are not provided as command-line options. It validates the
# format of the input.
#
# Globals:
#   START_TIME, END_TIME  Read/Written; YYMMDD-HHMM strings validated here.
#   MSG_TIME_*,
#   MSG_INVALID_TIME_FORMAT,
#   MSG_START_BEFORE_END  Read; localized prompt/error strings.
# Arguments:
#   None.
# Outputs:
#   Interactive prompts to stdout when values are missing.
# Returns:
#   0 on success; aborts via log_error on bad format or START >= END.
time_handler() {
  local t=""
  for t in START_TIME END_TIME; do
    local time=""

    if [[ -z "${!t}" ]]; then
      read -er -p "$(printf "${MSG_TIME_PROMPT}" "${t,,}")" time
    else
      time="${!t}"
    fi

    if [[ "${time}" =~ ^[0-9]{6}-[0-9]{4}$ ]]; then
      printf -v "${t}" "%s" "${time}"
    else
      log_error "$(printf "${MSG_INVALID_TIME_FORMAT}" "${t,,}" "${time}")"
    fi
  done

  # Validate start < end. `>=` rejects equal values because an empty range would
  # otherwise silently yield zero files — the error message already promises
  # strict ordering.
  if [[ ! "${START_TIME}" < "${END_TIME}" ]]; then
    log_error "$(printf "${MSG_START_BEFORE_END}" "${START_TIME}" "${END_TIME}")"
  fi
}

# Handles the SSH connection.
#
# This function checks for the SSH key, creates it if it doesn't exist, and
# copies it to the remote host. It also handles known hosts and retries the
# connection if it fails.
#
# Globals:
#   HOST         Read; target user@host.
#   SSH_KEY      Read; path to private key (auto-created if missing).
#   SSH_TIMEOUT  Read; connect timeout passed to ssh-copy-id.
#   HOME         Read; used to locate known_hosts.
#   MSG_SSH_*    Read; localized status and error messages.
# Arguments:
#   None.
# Outputs:
#   Debug/info/warn log messages; may invoke ssh-keygen, ssh-keyscan and
#   ssh-copy-id which write to stderr and known_hosts.
# Returns:
#   0 when SSH succeeds within max_retries (3); aborts via log_error otherwise.
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

    spinner_start "$(printf "${MSG_SPINNER_SSH}" "${HOST}")"
    if err_msg=$(execute_cmd "true" 2>&1); then
        spinner_stop
        log_debug "$(printf "${MSG_SSH_SUCCESS}" "${HOST}")"
        return 0
    fi
    spinner_stop

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
          log_warn "$(printf "${MSG_SSH_FAILED}" "${err_msg}")"
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
        ssh-keygen -R "${host_ip}" &>/dev/null || true
      fi
      log_info "$(printf "${MSG_SSH_HOST_KEY_ADD}" "${host_ip}")"
      ssh-keyscan -H "${host_ip}" >> "${known_hosts}" 2>/dev/null || true
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

  log_error "$(
    printf "${MSG_SSH_FINAL_FAILURE}\n" "${max_retries}"
    printf '  %s\n' "${err_msgs[@]}"
  )"
}

# Selects the best available file transfer tool.
#
# Checks for rsync, scp, and sftp in order. For rsync, also verifies the
# binary exists on the remote host (rsync requires both sides).
#
# Globals:
#   GET_LOG_TOOL              Written; first usable transfer tool name.
#   HOST                      Read; remote rsync probe is skipped in local mode.
#   MSG_RSYNC_NOT_AVAILABLE,
#   MSG_NO_TRANSFER_TOOLS     Read; localized warning / fatal messages.
# Arguments:
#   None.
# Outputs:
#   log_warn when rsync is missing on the remote; fatal log_error if no tool found.
# Returns:
#   0 on success; aborts via log_error if no transfer tool is available.
get_tools_checker() {
  local -r -a tools=("rsync" "scp" "sftp")
  local tool=""
  for tool in "${tools[@]}"; do
    if ! pkg_install_handler "${tool}"; then
      continue
    fi

    # rsync requires the binary on BOTH local and remote hosts
    if [[ "${tool}" == "rsync" && "${HOST}" != "local" ]]; then
      if ! execute_cmd "command -v rsync >/dev/null 2>&1"; then
        log_warn "${MSG_RSYNC_NOT_AVAILABLE}"
        continue
      fi
    fi

    GET_LOG_TOOL="${tool}"
    return 0
  done

  log_error "$(printf "${MSG_NO_TRANSFER_TOOLS}" "${tools[*]}")"
}

# Parses a special string.
#
# This function parses a special string in the format `<type:string>` and
# resolves it to a value.
#
# Globals:
#   REPLY_TYPE  Written; token type (env, cmd, date).
#   REPLY_STR   Written; resolved string value.
#   REPLY       Read; receives output from get_remote_value for env/cmd tokens.
#   MSG_INVALID_SPECIAL_STRING,
#   MSG_UNKNOWN_SPECIAL_STRING  Read; localized error messages.
# Arguments:
#   input: The special string to parse (without surrounding angle brackets).
# Outputs:
#   Debug traces via log_debug.
# Returns:
#   0 on success; aborts via log_error on malformed or unknown token type.
special_string_parser() {
  local -r input="${1:?"${FUNCNAME[0]} need input string."}"; shift

  if [[ ! "${input}" == *:* ]]; then
    log_error "$(printf "${MSG_INVALID_SPECIAL_STRING}" "${input}")"
  fi

  REPLY_TYPE="${input%%:*}"
  local str="${input#"${REPLY_TYPE}":}"
  log_debug "$(printf "${MSG_DBG_PARSED_SPECIAL}" "${REPLY_TYPE}" "${str}")"

  if [[ ${REPLY_TYPE} == "env"  || ${REPLY_TYPE} == "cmd" ]]; then
    get_remote_value "${REPLY_TYPE}" "${str}"
    REPLY_STR="${REPLY}"
  elif [[ ${REPLY_TYPE} == "date" ]]; then
    REPLY_STR="${str}"
  else
    log_error "$(printf "${MSG_UNKNOWN_SPECIAL_STRING}" "${REPLY_TYPE}")"
  fi

  log_debug "$(printf "${MSG_DBG_RESOLVED_STRING}" "${REPLY_STR}")"
}

# Handles path and pattern strings containing special tokens.
#
# This function takes a path and a pattern, finds all special tokens in the
# format `<...>`, and replaces them with their resolved values.
#
# Globals:
#   NUM, HOSTS    Read; used for <num> and <name> token substitution.
#   REPLY_PATH    Written; resolved directory path.
#   REPLY_PREFIX  Written; resolved file name pattern (date tokens deferred).
#   REPLY_TYPE,
#   REPLY_STR     Read; populated by special_string_parser.
#   MSG_TOKEN_NUM_NO_HOST  Read; localized warning.
# Arguments:
#   path_str:    The directory path to process.
#   pattern_str: The file name pattern to process.
# Outputs:
#   Debug traces and warnings via log_debug/log_warn.
# Returns:
#   0 on success; may abort via log_error through special_string_parser.
string_handler() {
  local path_str="${1:?"${FUNCNAME[0]} needs path argument."}"; shift
  local pattern_str="${1:?"${FUNCNAME[0]} needs pattern argument."}"; shift

  log_debug "$(printf "${MSG_DBG_ORIGINAL_PATH}" "${path_str}")"
  log_debug "$(printf "${MSG_DBG_ORIGINAL_PATTERN}" "${pattern_str}")"

  local str_name
  for str_name in path_str pattern_str; do
    local -n str_ref="${str_name}"
    local -a date_tokens=()
    local i=0

    # Resolve <num> and <name> tokens (simple replacements)
    if [[ "${str_ref}" == *"<num>"* ]]; then
      if [[ -n "${NUM}" ]]; then
        str_ref="${str_ref//<num>/${NUM}}"
      else
        log_warn "$(printf "${MSG_TOKEN_NUM_NO_HOST}" "<num>")"
        str_ref="${str_ref//<num>/}"
      fi
    fi
    if [[ "${str_ref}" == *"<name>"* ]]; then
      if [[ -n "${NUM}" && "${NUM}" =~ ^[1-9][0-9]*$ ]]; then
        str_ref="${str_ref//<name>/${HOSTS[${NUM}-1]%%::*}}"
      else
        log_warn "$(printf "${MSG_TOKEN_NUM_NO_HOST}" "<name>")"
        str_ref="${str_ref//<name>/}"
      fi
    fi
    while [[ "${str_ref}" =~ (<[^<>]*>) ]]; do
      local token="${BASH_REMATCH[1]}"

      # special case for date, need to process later
      if [[ "${token}" == "<date:"*">" ]]; then
        log_debug "$(printf "${MSG_DBG_DATE_TOKEN_DEFERRED}" "${token}")"
        date_tokens+=("${token}")
        str_ref="${str_ref//${token}/__DATE_TOKEN_${i}__}"
        (( i+=1 ))
        continue
      fi

      # normal case, replace directly
      log_debug "$(printf "${MSG_DBG_PROCESSING_TOKEN}" "${token}")"
      special_string_parser "${token:1:-1}"
      str_ref="${str_ref//${token}/${REPLY_STR}}"
    done

    local j
    for j in "${!date_tokens[@]}"; do
      str_ref="${str_ref/__DATE_TOKEN_${j}__/${date_tokens["${j}"]}}"
    done
  done

  REPLY_PATH="${path_str}"
  REPLY_PREFIX="${pattern_str}"
}

# Resolves <date:format> tokens remaining in REPLY_PATH using START_TIME.
#
# In LOG_PATHS, <date:> tokens in the file portion are kept for file_finder.
# But <date:> tokens in the path portion must be resolved to actual dates
# so the directory can be found.
# Resolves <date:> tokens in REPLY_PATH.
# When a path contains date tokens, generates all dates from START_TIME
# to END_TIME and returns an array of resolved paths.
#
# Globals:
#   REPLY_PATH   Read; path possibly containing a <date:fmt> token.
#   REPLY_PATHS  Written; array of resolved paths (one per date, or single
#                element when no date token is present).
#   REPLY        Read; receives epoch output from date_format.
#   START_TIME,
#   END_TIME     Read; define the inclusive range of dates to generate.
# Arguments:
#   None.
# Outputs:
#   None.
# Returns:
#   0 always.
resolve_path_dates() {
  local path="${REPLY_PATH}"

  if [[ ! "${path}" =~ (\<date:[^\<\>]*\>) ]]; then
    REPLY_PATHS=("${path}")
    return 0
  fi

  local token="${BASH_REMATCH[1]}"
  local fmt="${token#<date:}"
  fmt="${fmt%>}"

  # Generate all dates from START_TIME to END_TIME
  local start_epoch end_epoch
  date_format "${START_TIME}" "%s"; start_epoch="${REPLY}"
  date_format "${END_TIME}" "%s"; end_epoch="${REPLY}"

  # Determine step size from the smallest specifier present in fmt. Month and
  # year-only formats stay at the day default — the per-day expansion collapses
  # into the same directory string via the dedupe set below. Second-level
  # specifiers (%s/%S) would require 86400 iterations per day, so we warn and
  # fall back to day step instead; users hitting this need a coarser fmt.
  local step_sec=86400
  case "${fmt}" in
    *%s*|*%S*)
      log_warn "$(printf "${MSG_WARN_DATE_STEP_UNSUPPORTED}" "${token}")"
      ;;
    *%M*)        step_sec=60   ;;
    *%H*|*%k*|*%I*|*%l*) step_sec=3600 ;;
  esac

  # Batch-format every epoch in the range with a single `date -f -` call.
  # Replaces N forks (one per day) with 1, mirroring file_finder's tolerance
  # path. The trailing END_TIME entry guards against the loop missing the
  # final boundary when end_epoch isn't an exact step multiple.
  local -a epoch_lines=()
  local epoch="${start_epoch}"
  while [[ "${epoch}" -le "${end_epoch}" ]]; do
    epoch_lines+=("@${epoch}")
    epoch=$(( epoch + step_sec ))
  done
  epoch_lines+=("@${end_epoch}")

  local -a resolved_dates=()
  mapfile -t resolved_dates < <(printf '%s\n' "${epoch_lines[@]}" \
    | date -f - "+${fmt}" 2>/dev/null) || true

  local -a paths=()
  local -A seen=()
  local resolved_date resolved_path
  for resolved_date in "${resolved_dates[@]+"${resolved_dates[@]}"}"; do
    resolved_path="${path//${token}/${resolved_date}}"
    if [[ -z "${seen["${resolved_path}"]+set}" ]]; then
      paths+=("${resolved_path}")
      seen["${resolved_path}"]=1
    fi
  done

  REPLY_PATHS=("${paths[@]}")
}

# Finds files matching a name pattern and time range on local or remote host.
#
# For config files (no <date:> token), returns all matches directly.
# For dated files, extracts timestamps from filenames, filters by range,
# and expands boundaries by +/-1 to catch edge cases.
#
# Arguments:
#   paths:       Either a literal directory path string OR the name of an
#                indexed-array variable holding multiple directory paths.
#                Multiple paths are walked in a single `find` invocation,
#                which collapses N round-trips into one when called from a
#                date-expansion loop.
#   pattern:     Filename glob pattern (may contain at most one <date:>
#                token anywhere in the string).
#   start_time:  Range start in YYYYmmdd-HHMMSS format.
#   end_time:    Range end in YYYYmmdd-HHMMSS format.
#   use_sudo:    "true" to prefix the remote `find` and `stat` calls with
#                sudo (default "false").
#
# Globals:
#   HOST                       Read; controls local vs remote find.
#   FILE_TIME_TOLERANCE_MIN    Read; mtime expansion window.
#   REPLY_FILES                Written; array of matched file paths.
#   REPLY_RAW_COUNT            Written; number of files found by find before
#                              time filtering. Callers use this to distinguish
#                              "no pattern match" (0) from "no time match" (>0).
# Outputs:
#   Verbose/debug log lines; remote find/stat output piped internally.
# Returns:
#   0 on success (REPLY_FILES may be empty); non-zero only on fatal find error.
file_finder() {
  local _ff_first="${1:?"${FUNCNAME[0]} need path."}"; shift
  # First arg is either a literal path string or the name of an array
  # variable holding multiple paths. Probe via `declare -p` so that callers
  # passing a single dir keep working unchanged, while batched callers can
  # pass an array name to collapse N finds into one.
  local -a _ff_folder_paths=()
  local _ff_decl=""
  _ff_decl=$(declare -p "${_ff_first}" 2>/dev/null) || _ff_decl=""
  if [[ "${_ff_decl}" == "declare -a"* || "${_ff_decl}" == "declare -ar"* \
        || "${_ff_decl}" == "declare -ax"* ]]; then
    local -n _ff_ref="${_ff_first}"
    _ff_folder_paths=("${_ff_ref[@]}")
  else
    _ff_folder_paths=("${_ff_first}")
  fi
  local pattern="${1:-}"; shift
  local start_time="${1:?"${FUNCNAME[0]} need start time."}"; shift
  local end_time="${1:?"${FUNCNAME[0]} need end time."}"; shift
  local use_sudo="${1:-false}"; shift || true
  local sudo_prefix=""
  [[ "${use_sudo}" == "true" ]] && sudo_prefix="sudo "

  log_verbose "$(printf "${MSG_TRACE_INPUT}" "${FUNCNAME[0]}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "Paths" "${_ff_folder_paths[*]}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "Pattern" "${pattern}")"

  local token="" name_pattern="${pattern}"
  if [[ "${name_pattern}" =~ (<date:[^<>]*>) ]]; then
    token="${BASH_REMATCH[1]}"
    name_pattern="${name_pattern//${token}/*}"
  fi

  local format=""
  if [[ -n "${token}" ]]; then
    special_string_parser "${token:1:-1}"
    format="${REPLY_STR}"
  fi

  # Collapse consecutive * into single *
  name_pattern="${name_pattern//\*\*/*}"

  # Build a single find command that walks every starting path. find natively
  # accepts multiple starting points, so we collapse N round-trips into one.
  local _ff_paths_quoted="" _ff_p=""
  for _ff_p in "${_ff_folder_paths[@]}"; do
    [[ -z "${_ff_p}" ]] && continue
    printf -v _ff_paths_quoted "%s %q" "${_ff_paths_quoted}" "${_ff_p}"
  done
  # Escape single quotes in name_pattern so the generated -name '...' is safe.
  # Glob characters (* ?) must pass through unescaped for find to interpret.
  local _ff_name_esc="${name_pattern//\'/\'\\\'\'}"
  local find_cmd
  printf -v find_cmd "%sfind -L%s -maxdepth 1 \\( -type f -o -type l \\) -name '%s' 2>/dev/null | sort" \
    "${sudo_prefix}" "${_ff_paths_quoted}" "${_ff_name_esc}"

  # get file list
  local -a raw_files=()
  if ! mapfile -t raw_files < <(execute_cmd "${find_cmd}"); then
    REPLY_FILES=()
    REPLY_RAW_COUNT=0
    return 0
  fi
  REPLY_RAW_COUNT=${#raw_files[@]}

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
      all_files+=("${raw_files[${i}]}")
      file_timestamps+=("${BASH_REMATCH[1]}")
    fi
  done

  if [[ ${#all_files[@]} -eq 0 ]]; then
    REPLY_FILES=()
    return 0
  fi

  # [4] Unique Timestamps & Index Boundaries (sorted)
  local -a uniq_ts=()
  local ts="" last_ts=""
  while IFS= read -r ts; do
    if [[ "$ts" != "$last_ts" ]]; then
      uniq_ts+=( "$ts" )
      last_ts="$ts"
    fi
  done < <(printf '%s\n' "${file_timestamps[@]}" | sort)

  # Single pass over uniq_ts: compute s_idx (first ts >= start),
  # e_idx (last ts <= end), and has_exact_match (any ts in [start, end]).
  # Comparison style: use negated < / > so that "ts within [start, end]"
  # reads consistently across the function.
  local s_idx=-1 e_idx=-1
  local has_exact_match=false
  for i in "${!uniq_ts[@]}"; do
    ts="${uniq_ts[i]}"
    if [[ $s_idx -eq -1 ]] && [[ ! "${ts}" < "${formatted_start_ts}" ]]; then
      s_idx=$i
    fi
    if [[ ! "${ts}" > "${formatted_end_ts}" ]]; then
      e_idx=$i
      if [[ ! "${ts}" < "${formatted_start_ts}" ]]; then
        has_exact_match=true
      fi
    fi
  done

  if [[ "${has_exact_match}" == "true" ]]; then
    # --- Normal path: files exist in range → apply expansion ---
    # Case A: Found no start point? (All files are older than range)
    if [[ $s_idx -eq -1 ]]; then
       if [[ $e_idx -ne -1 ]]; then s_idx=0; fi
    fi
    # Case B: Found no end point?
    if [[ $e_idx -eq -1 ]]; then
       if [[ $s_idx -ne -1 ]]; then e_idx=$(( ${#uniq_ts[@]} - 1 )); fi
    fi

    # Apply Expansion (Safely)
    if [[ $s_idx -gt 0 ]]; then (( s_idx-- )); fi
    if [[ $e_idx -lt $(( ${#uniq_ts[@]} - 1 )) ]]; then (( ++e_idx )); fi

    local final_start_val="${uniq_ts[s_idx]}"
    local final_end_val="${uniq_ts[e_idx]}"
    log_debug "$(printf "${MSG_DBG_EXPANDED_RANGE}" "${s_idx}" "${e_idx}" "${final_start_val}" "${final_end_val}")"

    local -a selected=()
    for i in "${!all_files[@]}"; do
      ts="${file_timestamps[i]}"
      if [[ ! "$ts" < "$final_start_val" && ! "$ts" > "$final_end_val" ]]; then
        selected+=( "${all_files[${i}]}" )
      fi
    done
    REPLY_FILES=("${selected[@]}")
  else
    # --- Tolerance path: no exact match → check nearby files ---
    if [[ "${FILE_TIME_TOLERANCE_MIN:-0}" -le 0 ]]; then
      REPLY_FILES=()
    else
      local tolerance_sec=$(( FILE_TIME_TOLERANCE_MIN * 60 ))
      local start_epoch end_epoch
      date_format "${start_time}" "%s"; start_epoch="${REPLY}"
      date_format "${end_time}" "%s"; end_epoch="${REPLY}"

      # Build a ts -> epoch map in a single `date` invocation. On folders
      # with tens of thousands of files this replaces N forks with 1.
      local -A epoch_map=()
      if [[ "${format}" == "%s" ]]; then
        # Epoch format: timestamp IS the epoch; no parsing needed.
        for ts in "${uniq_ts[@]}"; do
          epoch_map["${ts}"]="${ts}"
        done
      else
        # Date string format: batch-parse YYYYMMDDHHMM[SS] via `date -f -`.
        # Strip non-digit characters first so formats like %Y%m%d-%H%M%S
        # (which produce "20260410-100238") are normalised to "20260410100238"
        # before positional extraction.
        local -a date_strs=()
        local stripped padded
        for ts in "${uniq_ts[@]}"; do
          stripped="${ts//[^0-9]/}"
          # Pad to at least 14 digits (YYYYMMDDHHmmss) so positional
          # extraction never yields empty fields for short formats like
          # %Y%m%d (8 digits) or %Y%m%d%H%M (12 digits).
          padded="${stripped}00000000000000"
          date_strs+=( "$(printf '%s-%s-%s %s:%s:%s' \
            "${padded:0:4}" "${padded:4:2}" "${padded:6:2}" \
            "${padded:8:2}" "${padded:10:2}" "${padded:12:2}")" )
        done
        local -a epochs=()
        mapfile -t epochs < <(printf '%s\n' "${date_strs[@]}" \
          | date -f - '+%s' 2>/dev/null) || true
        if [[ ${#epochs[@]} -eq ${#uniq_ts[@]} ]]; then
          local k
          for k in "${!uniq_ts[@]}"; do
            epoch_map["${uniq_ts[k]}"]="${epochs[k]}"
          done
        else
          # Batch parse failed → map stays empty and every candidate would
          # silently drop below. Surface a warning so users aren't confused by
          # a zero-file result caused by a date-tool issue.
          log_warn "$(printf "${MSG_WARN_FILE_FINDER_BATCH_FAILED}" "${#uniq_ts[@]}")"
        fi
      fi

      local -a selected=()
      for i in "${!all_files[@]}"; do
        ts="${file_timestamps[i]}"
        local file_epoch="${epoch_map[${ts}]:-}"
        [[ -z "${file_epoch}" ]] && continue

        local diff_start diff_end min_diff
        diff_start=$(( start_epoch - file_epoch ))
        diff_end=$(( file_epoch - end_epoch ))
        if [[ $diff_start -gt 0 ]]; then
          min_diff=$diff_start
        elif [[ $diff_end -gt 0 ]]; then
          min_diff=$diff_end
        else
          min_diff=0
        fi

        if [[ $min_diff -le $tolerance_sec ]]; then
          selected+=( "${all_files[${i}]}" )
        fi
      done
      REPLY_FILES=("${selected[@]+"${selected[@]}"}")
    fi
  fi

  # [6] mtime fallback: check unselected files by modification time.
  # Always enabled — a file whose name timestamp predates the range may still
  # have been actively written during the range (e.g. glog, corenavi_auto).
  if [[ -n "${token}" && ${#raw_files[@]} -gt 0 ]]; then
    local mtime_start_epoch
    date_format "${start_time}" "%s"; mtime_start_epoch="${REPLY}"

    local -A selected_set=()
    local f
    for f in "${REPLY_FILES[@]+"${REPLY_FILES[@]}"}"; do
      selected_set["${f}"]=1
    done

    # Only consider files whose filename timestamp predates the range start.
    # Files created after the range couldn't have been writing during it.
    local -A pre_range_set=()
    for i in "${!all_files[@]}"; do
      if [[ "${file_timestamps[i]}" < "${formatted_start_ts}" ]]; then
        pre_range_set["${all_files[i]}"]=1
      fi
    done

    # Collect unselected pre-range files and stat them in one batched call.
    local -a unselected=()
    for f in "${raw_files[@]}"; do
      [[ -n "${selected_set["${f}"]+set}" ]] && continue
      [[ -n "${pre_range_set["${f}"]+set}" ]] || continue
      unselected+=("${f}")
    done

    if [[ ${#unselected[@]} -gt 0 ]]; then
      local quoted_args="" stat_out
      for f in "${unselected[@]}"; do
        quoted_args+=" $(printf '%q' "${f}")"
      done
      # Single stat call: '%Y|%n' lets us split mtime from path even if path
      # contains spaces. Errors (missing/permission) go to stderr; surviving
      # entries still appear on stdout, matching the prior graceful-skip behavior.
      # A file with mtime >= start means it was still being written during the range.
      # We don't check <= end because a continuously written log that spans past
      # the range end was clearly also active during the range.
      if stat_out=$(execute_cmd "${sudo_prefix}stat -c '%Y|%n'${quoted_args} 2>/dev/null"); then
        local -A mtime_map=()
        local line ts path
        while IFS= read -r line; do
          [[ -z "${line}" ]] && continue
          ts="${line%%|*}"
          path="${line#*|}"
          mtime_map["${path}"]="${ts}"
        done <<< "${stat_out}"

        for f in "${unselected[@]}"; do
          local file_mtime="${mtime_map[${f}]:-}"
          [[ -z "${file_mtime}" ]] && continue
          if [[ "${file_mtime}" -ge "${mtime_start_epoch}" ]]; then
            REPLY_FILES+=("${f}")
          fi
        done
      fi
    fi
  fi

  if [[ "${#REPLY_FILES[@]}" -gt 0 ]]; then
    log_info "$(printf "${MSG_FILES_SELECTED}" "${#REPLY_FILES[@]}" "${#raw_files[@]}")"
  fi
}

# Creates the output folder.
#
# If SAVE_FOLDER contains tokens (<num>, <name>, <date:format>), they are
# resolved and the result is used directly. Otherwise the default suffix
# (_hostname_timestamp) is appended.
#
# Supported tokens:
#   <num>          Host number (from -n option)
#   <name>         Host display name (from HOSTS array)
#   <date:format>  START_TIME formatted with strftime format
#
# Globals:
#   SAVE_FOLDER  Read/written; resolved to a final absolute path.
#   NUM, HOSTS, HOST, START_TIME  Read; used for token resolution and default suffix.
#   MSG_TOKEN_NUM_NO_HOST         Read; localized warning when token cannot resolve.
# Arguments:
#   None.
# Outputs:
#   Calls create_folder which may emit fatal log_error on failure.
# Returns:
#   0 on success; aborts via log_error if folder creation fails.
folder_creator() {
  if [[ "${SAVE_FOLDER}" == *"<"* ]]; then
    # Resolve <num> token
    if [[ "${SAVE_FOLDER}" == *"<num>"* ]]; then
      if [[ -n "${NUM}" ]]; then
        SAVE_FOLDER="${SAVE_FOLDER//<num>/${NUM}}"
      else
        log_warn "$(printf "${MSG_TOKEN_NUM_NO_HOST}" "<num>")"
        SAVE_FOLDER="${SAVE_FOLDER//<num>/}"
      fi
    fi

    # Resolve <name> token
    if [[ "${SAVE_FOLDER}" == *"<name>"* ]]; then
      if [[ -n "${NUM}" && "${NUM}" =~ ^[1-9][0-9]*$ ]]; then
        SAVE_FOLDER="${SAVE_FOLDER//<name>/${HOSTS[${NUM}-1]%%::*}}"
      else
        log_warn "$(printf "${MSG_TOKEN_NUM_NO_HOST}" "<name>")"
        SAVE_FOLDER="${SAVE_FOLDER//<name>/}"
      fi
    fi

    # Resolve <date:format> tokens
    local token="" fmt="" resolved=""
    while [[ "${SAVE_FOLDER}" =~ (\<date:[^\<\>]*\>) ]]; do
      token="${BASH_REMATCH[1]}"
      fmt="${token#<date:}"
      fmt="${fmt%>}"
      date_format "${START_TIME}" "${fmt}"
      resolved="${REPLY}"
      SAVE_FOLDER="${SAVE_FOLDER//${token}/${resolved}}"
    done
  else
    local host_label
    if [[ -n "${NUM}" && "${NUM}" =~ ^[1-9][0-9]*$ ]]; then
      # -n mode: use HOSTS display name
      host_label="${HOSTS[${NUM}-1]%%::*}"
    else
      # -l or -u mode: use hostname
      if ! host_label=$(execute_cmd "hostname"); then
        log_error "$(printf "${MSG_HOSTNAME_DATE_FAILED}" "${HOST}")"
      fi
    fi

    local timestamp
    if ! timestamp=$(execute_cmd "date +%y%m%d-%H%M%S"); then
      log_error "$(printf "${MSG_HOSTNAME_DATE_FAILED}" "${HOST}")"
    fi

    SAVE_FOLDER="${SAVE_FOLDER}_${host_label}_${timestamp}"
  fi

  # Place in /tmp when SAVE_FOLDER is a relative path (no -o with absolute path)
  if [[ "${SAVE_FOLDER}" != /* ]]; then
    SAVE_FOLDER="/tmp/${SAVE_FOLDER}"
  fi

  create_folder "${SAVE_FOLDER}"
}

# Writes a summary of user inputs and LOG_PATHS to script.log in SAVE_FOLDER.
#
# Globals:
#   HOST, START_TIME, END_TIME, GET_LOG_TOOL, SAVE_FOLDER, LOG_PATHS  Read.
#   MSG_USER_INPUTS_SUMMARY  Read; localized header.
# Arguments:
#   None.
# Outputs:
#   Info log lines locally; appends summary to ${SAVE_FOLDER}/script.log on host.
# Returns:
#   0 on success; non-zero if remote write fails.
save_script_data() {
  local -a string_array=(
    "$(printf "${MSG_SUMMARY_HOST}" "${HOST}")"
    "$(printf "${MSG_SUMMARY_TIME_RANGE}" "${START_TIME}" "${END_TIME}")"
    "$(printf "${MSG_SUMMARY_TOOL}" "${GET_LOG_TOOL}")"
    "$(printf "${MSG_SUMMARY_SAVE_FOLDER}" "${SAVE_FOLDER}")"
    )

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

  if (( ${#LOG_PATHS[@]} % 3 != 0 )); then
    log_warn "LOG_PATHS has ${#LOG_PATHS[@]} elements (not a multiple of 3). Check configuration."
  fi

  local lp_i
  for (( lp_i=0; lp_i<${#LOG_PATHS[@]}; lp_i+=3 )); do
    local lp_path="${LOG_PATHS[lp_i]}"
    local lp_pattern="${LOG_PATHS[lp_i+1]}"
    local lp_flags="${LOG_PATHS[lp_i+2]}"
    local escaped_path="${lp_path//\'/\'\\\'\'}"
    local escaped_pattern="${lp_pattern//\'/\'\\\'\'}"
    local escaped_flags="${lp_flags//\'/\'\\\'\'}"
    remote_cmd+="printf '  %s :: %s :: %s\n' '${escaped_path}' '${escaped_pattern}' '${escaped_flags}' >> ${script_log}; "
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
#   SAVE_FOLDER  Read; the path of the folder to be removed.
#   HOST         Read; controls local vs remote rm via execute_cmd.
#   MSG_NO_SAVE_FOLDER, MSG_FOLDER_REMOVE_FAILED  Read; localized messages.
# Arguments:
#   None.
# Outputs:
#   Debug/log lines; closes log file before returning.
# Returns:
#   0 always (best-effort cleanup).
file_cleaner() {
  spinner_stop
  if [[ -z "${SAVE_FOLDER}" ]]; then
    log_debug "${MSG_NO_SAVE_FOLDER}"
    close_log_file
    return 0
  fi

  local rm_cmd
  printf -v rm_cmd "rm -rf %q" "${SAVE_FOLDER}"
  readonly rm_cmd

  if ! execute_cmd "${rm_cmd}"; then
    log_warn "$(printf "${MSG_FOLDER_REMOVE_FAILED}" "${SAVE_FOLDER}")"
  else
    log_debug "$(printf "${MSG_FOLDER_REMOVED}" "${SAVE_FOLDER}")"
  fi
  close_log_file
}

# Creates a .tar.gz archive of SAVE_FOLDER alongside the folder itself.
# Archive path: ${SAVE_FOLDER}.tar.gz
# Original folder is preserved.
#
# Globals:
#   SAVE_FOLDER  Read; absolute path of the folder to archive.
#   MSG_ARCHIVE_NO_FOLDER, MSG_ARCHIVING, MSG_ARCHIVE_FAILED, MSG_ARCHIVE_DONE
#                Read; i18n message templates used for log output.
# Arguments:
#   None.
# Outputs:
#   Writes progress / success / failure messages via log_info / log_warn.
# Returns:
#   0 on success.
#   1 on failure (any partial/corrupted archive is removed before returning).
archive_save_folder() {
  if [[ -z "${SAVE_FOLDER}" || ! -d "${SAVE_FOLDER}" ]]; then
    log_warn "$(printf "${MSG_ARCHIVE_NO_FOLDER}" "${SAVE_FOLDER}")"
    return 1
  fi

  local archive_path="${SAVE_FOLDER}.tar.gz"
  local parent_dir base_name
  parent_dir="$(dirname "${SAVE_FOLDER}")"
  base_name="$(basename "${SAVE_FOLDER}")"

  log_debug "$(printf "${MSG_ARCHIVING}" "${archive_path}")"

  spinner_start "${MSG_SPINNER_ARCHIVE}"
  if ! tar -czf "${archive_path}" -C "${parent_dir}" "${base_name}"; then
    spinner_stop
    rm -f "${archive_path}"
    log_warn "$(printf "${MSG_ARCHIVE_FAILED}" "${archive_path}")"
    return 1
  fi
  spinner_stop

  local archive_size
  archive_size="$(du -h --apparent-size "${archive_path}" | cut -f1)"
  log_debug "$(printf "${MSG_ARCHIVE_DONE}" "${archive_path}" "${archive_size}")"
  return 0
}

# Copies matched files into the SAVE_FOLDER on local or remote host.
#
# Strips /home/<user>/ prefix from paths to keep output structure clean.
# Uses xargs with null-delimited input to handle filenames safely.
#
# Globals:
#   SAVE_FOLDER  Read; destination directory on local or remote host.
#   HOST         Read via execute_cmd_from_array.
# Arguments:
#   log_path: The resolved source directory path.
#   ...:      File paths to copy.
# Outputs:
#   Verbose log lines; cp/install output from the executed command.
# Returns:
#   The exit status of the underlying copy command.
file_copier() {
  local log_path="${1:?"${FUNCNAME[0]} need log path."}"; shift
  local -a fc_log_files=("$@")

  log_verbose "$(printf "${MSG_TRACE_INPUT}" "${FUNCNAME[0]}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "log_path" "${log_path}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "files count" "${#fc_log_files[@]}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "SAVE_FOLDER" "${SAVE_FOLDER}")"
  log_verbose "$(printf "${MSG_TRACE_PARAM}" "HOST" "${HOST}")"

  if [[ ${#fc_log_files[@]} -eq 0 ]]; then
    log_warn "$(printf "${MSG_NO_FILES_TO_COPY}" "${log_path}")"
    return 0
  fi

  if [[ "${log_path}" == /home/*/*  ]]; then
    log_path="${log_path#/home/*/}"
  fi

  local save_path="${SAVE_FOLDER}/${log_path}"
  create_folder "${save_path}"

  local -a cp_opts=("-r")
  if [[ "${VERBOSE:-0}" -ge 1 ]]; then
    cp_opts+=("-v")
  fi

  # Construct the xargs command (use _SUDO_PREFIX if set by get_log)
  local xargs_cmd
  printf -v xargs_cmd "xargs -0 -r %scp %s -t %q" "${_SUDO_PREFIX:-}" "${cp_opts[*]}" "${save_path}/"

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
#
# Globals:
#   GET_LOG_TOOL                 Read; selected transfer tool.
#   HOST, SAVE_FOLDER, SSH_KEY,
#   SSH_OPTS                     Read; transfer endpoint and credentials.
#   TRANSFER_MAX_RETRIES,
#   TRANSFER_RETRY_DELAY,
#   TRANSFER_SIZE_WARN_MB        Read; retry / size-warning policy.
#   MSG_TRANSFER_*, MSG_RETRIEVE_MANUALLY  Read; localized progress / errors.
# Arguments:
#   None.
# Outputs:
#   Transfer-tool stdout/stderr; interactive prompt on persistent failure.
# Returns:
#   0 on success; 1 if transfer ultimately fails after retries.
file_sender() {
  local -r tool="${GET_LOG_TOOL}"
  # Default: show overall transfer progress (--info=progress2)
  # Verbose: add per-file detail (-v --progress)
  # --partial: keep partially transferred files (resume on retry)
  # --timeout: rsync-level I/O timeout (complements SSH ServerAliveInterval)
  local -a rsync_flags=("-a" "-z" "--info=progress2" "--partial" "--timeout=60")
  local -a scp_flags=("-p" "-r")
  local sftp_progress="progress\n" sftp_output="/dev/stdout"

  local -a sftp_flags=()

  # Apply bandwidth limit if configured
  if [[ "${BANDWIDTH_LIMIT:-0}" -gt 0 ]]; then
    rsync_flags+=("--bwlimit=${BANDWIDTH_LIMIT}")
    # scp and sftp use -l in Kbit/s; convert KB/s -> Kbit/s (* 8)
    local kbits=$(( BANDWIDTH_LIMIT * 8 ))
    scp_flags+=("-l" "${kbits}")
    sftp_flags+=("-l" "${kbits}")
  fi

  if [[ "${VERBOSE:-0}" -ge 1 ]]; then
    rsync_flags+=("-v" "--progress")
    scp_flags+=("-v")
  fi

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

  # Single SSH `du -sb` traverses the tree once; format human-readable locally
  # in pure bash. Saves one round-trip on every run (was -sh + -sb).
  local size_bytes folder_size=""
  spinner_start "${MSG_SPINNER_SIZE}"
  size_bytes=$(execute_cmd "du -sb ${remote_esc} | awk '{print \$1}'")
  spinner_stop
  size_bytes="${size_bytes//[^0-9]/}"
  : "${size_bytes:=0}"
  if   (( size_bytes < 1024 ));        then folder_size="${size_bytes}B"
  elif (( size_bytes < 1048576 ));     then folder_size="$((size_bytes/1024))K"
  elif (( size_bytes < 1073741824 ));  then folder_size="$((size_bytes/1048576))M"
  else                                      folder_size="$((size_bytes/1073741824))G"
  fi
  log_info "$(printf "${MSG_REMOTE_FOLDER_SIZE}" "${SAVE_FOLDER}" "${folder_size}")"

  # Check if folder size exceeds warning threshold
  if [[ "${TRANSFER_SIZE_WARN_MB:-0}" -gt 0 ]]; then
    local size_mb=$(( size_bytes / 1024 / 1024 ))
    if [[ "${size_mb}" -ge "${TRANSFER_SIZE_WARN_MB}" ]]; then
      local confirm=""
      log_warn "$(printf "${MSG_SIZE_EXCEED_CONFIRM}" "${TRANSFER_SIZE_WARN_MB}" "${folder_size}")"
      read -r confirm </dev/tty 2>/dev/null || read -r confirm
      if [[ "${confirm,,}" == "n" || "${confirm,,}" == "no" ]]; then
        log_info "${MSG_TRANSFER_CANCELLED}"
        return 1
      fi
    fi
  fi

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
          sftp "${sftp_flags[@]}" "${SSH_OPTS[@]}" \
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

    (( ++attempt ))
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
}

# Dry-run variant of get_log: finds and lists files without copying.
#
# Globals:
#   LOG_PATHS, START_TIME, END_TIME  Read; configuration for the search.
#   REPLY_PATH, REPLY_PREFIX, REPLY_PATHS,
#   REPLY_FILES                      Read; populated by string_handler /
#                                    resolve_path_dates / file_finder.
#   MSG_DRY_RUN_*, MSG_NO_FILES_FOUND  Read; localized output strings.
# Arguments:
#   None.
# Outputs:
#   Info / warn log lines listing matched files per LOG_PATHS entry.
# Returns:
#   0 always.
get_log_dry_run() {
  if (( ${#LOG_PATHS[@]} % 3 != 0 )); then
    log_warn "LOG_PATHS has ${#LOG_PATHS[@]} elements (not a multiple of 3). Check configuration."
  fi

  local log_path="" log_pattern="" log_flags=""
  local total=$(( ${#LOG_PATHS[@]} / 3 ))
  local idx=0
  local grand_total=0
  local i

  for (( i=0; i<${#LOG_PATHS[@]}; i+=3 )); do
    log_path="${LOG_PATHS[i]}"
    log_pattern="${LOG_PATHS[i+1]}"
    log_flags="${LOG_PATHS[i+2]}"
    (( ++idx ))

    string_handler "${log_path}" "${log_pattern}"
    local use_sudo=false
    if _needs_sudo "${REPLY_PATH}" "${log_flags}"; then
      use_sudo=true
    fi
    resolve_path_dates
    local pattern="${REPLY_PREFIX}"

    local path_found=false
    local rpath=""
    for rpath in "${REPLY_PATHS[@]}"; do
      log_info "$(printf "${MSG_RESOLVED_PATH}" "${idx}" "${total}" "${rpath}" "${pattern}")"

      if [[ -z "${rpath}" ]]; then
        log_warn "$(printf "${MSG_EMPTY_PATH}" "${idx}" "${total}")"
        continue
      fi

      log_info "$(printf "${MSG_DRY_RUN_RESOLVED}" "${rpath}")"
      log_info "$(printf "${MSG_DRY_RUN_PATTERN}" "${pattern}")"

      if ! execute_cmd "test -d $(printf '%q' "${rpath}")"; then
        log_warn "$(printf "${MSG_DRY_RUN_DIR_NOT_FOUND}" "${rpath}")"
        continue
      fi

      file_finder "${rpath}" "${pattern}" "${START_TIME}" "${END_TIME}" "${use_sudo}"
      local -a files=("${REPLY_FILES[@]+"${REPLY_FILES[@]}"}")

      if [[ "${#files[@]}" -gt 0 ]]; then
        path_found=true
        log_info "$(printf "${MSG_DRY_RUN_WOULD_COPY}" "${#files[@]}")"
        local f
        for f in "${files[@]}"; do
          log_info "  ${f}"
        done
        (( grand_total += ${#files[@]} ))
      else
        if [[ "${REPLY_RAW_COUNT:-0}" -eq 0 ]]; then
          log_warn "$(printf "${MSG_NO_PATTERN_MATCH}" "${idx}" "${total}" "${pattern}")"
        else
          log_warn "$(printf "${MSG_NO_TIME_MATCH}" "${idx}" "${total}" "${REPLY_RAW_COUNT}" "${START_TIME}" "${END_TIME}")"
        fi
      fi
    done

    if [[ "${path_found}" == "false" ]]; then
      log_warn "$(printf "${MSG_NO_FILES_FOUND}" "${idx}" "${total}")"
    fi
  done

  log_info "$(printf "${MSG_DRY_RUN_TOTAL}" "${grand_total}")"
}

# Main function for getting the logs.
#
# This function iterates over the `LOG_PATHS` array, finds the log files, and
# copies them to the output folder.
#
# Globals:
#   LOG_PATHS, START_TIME, END_TIME, SAVE_FOLDER  Read; configuration / target.
#   REPLY_PATH, REPLY_PREFIX,
#   REPLY_PATHS, REPLY_FILES                      Read; populated by helpers.
#   MSG_NO_FILES_FOUND, MSG_NO_FILES_IN_RANGE     Read; localized warnings.
# Arguments:
#   None.
# Outputs:
#   Info / warn log lines per processed LOG_PATHS entry.
# Returns:
#   0 on success.
get_log() {
  if (( ${#LOG_PATHS[@]} % 3 != 0 )); then
    log_warn "LOG_PATHS has ${#LOG_PATHS[@]} elements (not a multiple of 3). Check configuration."
  fi

  local total=$(( ${#LOG_PATHS[@]} / 3 ))
  local i

  # Single resolution pass: each LOG_PATHS entry is run through string_handler
  # exactly once, and _needs_sudo exactly once. Results are cached in parallel
  # arrays so the main loop below can reuse them without re-resolving tokens
  # or re-checking sudo for every date-expanded path.
  local -a _resolved_path=() _resolved_pattern=()
  local -a _resolved_sudo=()
  for (( i=0; i<${#LOG_PATHS[@]}; i+=3 )); do
    string_handler "${LOG_PATHS[i]}" "${LOG_PATHS[i+1]}"
    _resolved_path+=("${REPLY_PATH}")
    _resolved_pattern+=("${REPLY_PREFIX}")
    if _needs_sudo "${REPLY_PATH}" "${LOG_PATHS[i+2]}"; then
      _resolved_sudo+=("true")
    else
      _resolved_sudo+=("false")
    fi
  done

  # Authenticate sudo upfront if any entry needs it (preserves the original
  # UX of prompting for the password before the find loop starts).
  local _sudo_authenticated=false
  local k
  for k in "${!_resolved_sudo[@]}"; do
    if [[ "${_resolved_sudo[k]}" == "true" ]]; then
      log_info "$(printf "${MSG_SUDO_REQUIRED}" "${_resolved_path[k]}")"
      if execute_cmd "sudo -v"; then
        _sudo_authenticated=true
      else
        log_warn "$(printf "${MSG_SUDO_FAILED}" "${_resolved_path[k]}")"
      fi
      break
    fi
  done

  local _total_files_found=0
  local idx=0
  for k in "${!_resolved_path[@]}"; do
    REPLY_PATH="${_resolved_path[k]}"
    local pattern="${_resolved_pattern[k]}"
    local use_sudo=false
    [[ "${_resolved_sudo[k]}" == "true" ]] && use_sudo=true
    (( ++idx ))

    resolve_path_dates

    # Collect non-empty rpaths into a single array; one entry-level log line
    # captures the resolved path template (still containing the date token,
    # which is more useful than 30 nearly-identical expanded paths).
    local -a entry_paths=()
    local rpath=""
    local _had_empty_path=false
    for rpath in "${REPLY_PATHS[@]}"; do
      if [[ -z "${rpath}" ]]; then
        _had_empty_path=true
        continue
      fi
      entry_paths+=("${rpath}")
    done
    log_info "$(printf "${MSG_RESOLVED_PATH}" "${idx}" "${total}" "${REPLY_PATH}" "${pattern}")"

    if [[ "${_had_empty_path}" == "true" && "${#entry_paths[@]}" -eq 0 ]]; then
      log_warn "$(printf "${MSG_EMPTY_PATH}" "${idx}" "${total}")"
      continue
    fi
    if [[ "${#entry_paths[@]}" -eq 0 ]]; then
      log_warn "$(printf "${MSG_NO_FILES_FOUND}" "${idx}" "${total}")"
      continue
    fi

    # Single batched find across every expanded path for this entry.
    spinner_start "$(printf "${MSG_SPINNER_FINDING}" "${idx}" "${total}")"
    file_finder entry_paths "${pattern}" "${START_TIME}" "${END_TIME}" "${use_sudo}"
    spinner_stop
    local -a all_found_files=("${REPLY_FILES[@]+"${REPLY_FILES[@]}"}")

    # Group results back to their source rpath via longest-prefix match,
    # then dispatch to file_copier per group so the per-day directory
    # structure under SAVE_FOLDER is preserved.
    if [[ "${#all_found_files[@]}" -gt 0 ]]; then
      local -A files_by_path=()
      local f="" matched_rp="" rp=""
      for f in "${all_found_files[@]}"; do
        matched_rp=""
        for rp in "${entry_paths[@]}"; do
          if [[ "${f}" == "${rp}/"* ]] && (( ${#rp} > ${#matched_rp} )); then
            matched_rp="${rp}"
          fi
        done
        if [[ -n "${matched_rp}" ]]; then
          files_by_path["${matched_rp}"]+="${f}"$'\n'
        fi
      done

      _SUDO_PREFIX=""; [[ "${use_sudo}" == "true" ]] && _SUDO_PREFIX="sudo "
      for rp in "${entry_paths[@]}"; do
        [[ -n "${files_by_path[${rp}]+set}" ]] || continue
        local -a group=()
        mapfile -t group <<< "${files_by_path[${rp}]%$'\n'}"
        spinner_start "$(printf "${MSG_SPINNER_COPYING}" "${idx}" "${total}" "${#group[@]}")"
        file_copier "${rp}" "${group[@]}"
        spinner_stop
      done
      _SUDO_PREFIX=""
    fi

    if [[ "${#all_found_files[@]}" -eq 0 ]]; then
      # Diagnose why no files were found
      local _dir_missing=false _check_cmd=""
      for rp in "${entry_paths[@]}"; do
        printf -v _check_cmd "test -d %q" "${rp}"
        if ! execute_cmd "${_check_cmd}"; then
          _dir_missing=true
          log_warn "$(printf "${MSG_DIR_NOT_FOUND}" "${idx}" "${total}" "${rp}")"
        fi
      done
      if [[ "${_dir_missing}" == "false" ]]; then
        if [[ "${REPLY_RAW_COUNT:-0}" -eq 0 ]]; then
          log_warn "$(printf "${MSG_NO_PATTERN_MATCH}" "${idx}" "${total}" "${pattern}")"
        else
          log_warn "$(printf "${MSG_NO_TIME_MATCH}" "${idx}" "${total}" "${REPLY_RAW_COUNT}" "${START_TIME}" "${END_TIME}")"
        fi
      fi
    else
      log_info "$(printf "${MSG_FOUND_COPYING}" "${idx}" "${total}" "${#all_found_files[@]}")"
      _total_files_found=$(( _total_files_found + ${#all_found_files[@]} ))
    fi
  done

  if [[ "${_total_files_found}" -eq 0 && "${total}" -gt 0 ]]; then
    log_warn "$(printf "${MSG_NO_FILES_IN_RANGE}" "${START_TIME}" "${END_TIME}")"
  fi
}

# Main function.
#
# This is the main function of the script. It parses the command-line
# options, handles the host and time selection, checks for the SSH
# connection, and then gets the logs.
#
# Globals:
#   LANG_CODE, LANG, HOST, NUM, START_TIME, END_TIME, SAVE_FOLDER,
#   DRY_RUN, GET_LOG_TOOL  Read/written across the pipeline.
# Arguments:
#   $@: Forwarded to option_parser.
# Outputs:
#   Drives all step messages, prompts, and final output paths.
# Returns:
#   0 on full success; non-zero / log_error abort on any fatal failure.
main() {
  # Belt-and-suspenders: guarantee no spinner process leaks on any exit path
  # (set -e failure, unhandled error, explicit exit from nested helpers).
  trap spinner_stop EXIT
  option_parser "$@"

  if [[ -z "${LANG_CODE}" ]]; then
    case "${LANG:-}" in
      zh_TW*) LANG_CODE="zh-TW" ;; zh_CN*|zh_SG*) LANG_CODE="zh-CN" ;;
      ja*) LANG_CODE="ja" ;; *) LANG_CODE="en" ;;
    esac
  fi
  load_lang

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "${MSG_DRY_RUN_BANNER}"
  fi

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

  # Pre-resolve every <env:>/<cmd:> token in LOG_PATHS in one batch round-trip
  # so subsequent get_remote_value calls hit the cache instead of paying the
  # SSH RTT cost per unique token. Best-effort: failures fall through to lazy
  # resolution. Only meaningful for remote HOST.
  if [[ "${HOST}" != "local" ]]; then
    spinner_start "${MSG_SPINNER_TOKEN}"
    prefetch_token_cache
    spinner_stop
  fi

  log_info "${MSG_STEP4}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    get_log_dry_run
    log_info "${MSG_DRY_RUN_COMPLETE}"
  else
    folder_creator
    init_log_file

    # file_cleaner removes the temp folder; append `exit 130` so Ctrl-C actually
    # aborts the script instead of resuming after cleanup.
    trap 'file_cleaner; exit 130' SIGINT SIGTERM

    save_script_data
    get_log

    if [[ "${HOST}" != "local" ]]; then
      log_info "$(printf "${MSG_STEP5_TRANSFER}" "${GET_LOG_TOOL}")"
      while ! file_sender; do
        local choice=""
        log_warn "${MSG_TRANSFER_CHOICE}"
        read -r choice </dev/tty 2>/dev/null || read -r choice
        case "${choice,,}" in
          k|keep)
            log_info "$(printf "${MSG_REMOTE_PRESERVED}" "${HOST}" "${SAVE_FOLDER}")"
            close_log_file; exit 1 ;;
          c|clean)
            file_cleaner
            close_log_file; exit 1 ;;
          *)  # retry (default: empty or 'r')
            log_info "${MSG_RETRY_TRANSFER}"
            continue ;;
        esac
      done
    else
      log_info "${MSG_STEP5_LOCAL}"
    fi

    # Step 6: Archive the collected folder
    log_info "${MSG_STEP6_ARCHIVE}"
    while ! archive_save_folder; do
      local choice=""
      log_warn "${MSG_ARCHIVE_CHOICE}"
      read -r choice </dev/tty 2>/dev/null || read -r choice
      case "${choice,,}" in
        k|keep)
          log_info "$(printf "${MSG_ARCHIVE_KEEP_FOLDER}" "${SAVE_FOLDER}")"
          break ;;
        a|abort)
          log_info "$(printf "${MSG_ARCHIVE_ABORTED}" "${SAVE_FOLDER}")"
          close_log_file; exit 1 ;;
        *)  # retry (default: empty or 'r')
          log_info "${MSG_RETRY_ARCHIVE}"
          continue ;;
      esac
    done

    log_info "${MSG_OUTPUT_SECTION}"
    log_info "$(printf "${MSG_OUTPUT_NAME}" "${SAVE_FOLDER}")"
    if [[ -f "${SAVE_FOLDER}.tar.gz" ]]; then
      log_info "$(printf "${MSG_OUTPUT_ARCHIVE}" "${SAVE_FOLDER}.tar.gz")"
    fi
    log_info "${MSG_SUCCESS}"
    close_log_file
  fi
}

# Allow sourcing without executing main.
# "return" succeeds when sourced but fails when executed directly.
(return 0 2>/dev/null) || main "$@"
