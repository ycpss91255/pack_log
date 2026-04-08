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
#   ./pack_log.sh -n 1 -s 260101-0000 -e 260101-2359
#   ./pack_log.sh -u myuser@10.90.68.188 -s 260101-0000 -e 260101-2359
#   ./pack_log.sh -l -s 260101-0000 -e 260101-2359
#
# For more information, run the script with the --help option.
#
# Author: Yunchien.chen <yunchien.chen@coretronic-robotics.com>
# Date: 2026-04-08
# Version: 1.6.2

# shellcheck disable=SC2059  # i18n: MSG_* variables used as printf format strings by design
# shellcheck disable=SC2029  # SSH commands piped via stdin, not affected
# shellcheck disable=SC2016  # Single-quoted <env:> tokens are resolved by string_handler, not bash

set +u 2>/dev/null # KCOV_EXCL_LINE
declare _PACK_LOG_SCRIPT_NAME # KCOV_EXCL_LINE
_PACK_LOG_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}" .sh)" # KCOV_EXCL_LINE
readonly _PACK_LOG_SCRIPT_NAME # KCOV_EXCL_LINE

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
#   "<env:HOME>/log_core"              "app.<cmd:hostname>.log.<date:%Y%m%d-%H%M%S>*"  "<mtime>"
#   "/var/log"                         "syslog*"                               "<sudo>"
#   "<env:HOME>/log_core"              "app.*.<date:%Y%m%d-%H%M%S>*"           "<mtime><sudo>"

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
  # PATH                                                                  FILE_PATTERN                                                      FLAGS
  # AvoidStop (pana-04, local test with symlink dirs)
  # "<env:HOME>/Desktop/pack_log/log/avoid/core_storage/default"           "uimap.png"                                                        ""
  # "<env:HOME>/Desktop/pack_log/log/avoid/core_storage/default2"          "uimap.yaml"                                                       ""
  # "<env:HOME>/Desktop/pack_log/log/avoid/log/AvoidStop_<date:%Y-%m-%d>"  "<date:%Y-%m-%d-%H.%M.%S>_*<suffix:_avoid.png>"                    ""
  # "<env:HOME>/Desktop/pack_log/log/avoid/log_core"                       "corenavi_auto.pana-04.myuser.log.INFO.<date:%Y%m%d-%H%M%S>*"      "<mtime>"
  # "<env:HOME>/Desktop/pack_log/log/avoid/log_slam/record"                "coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*<suffix:.rec>"               ""


  # # Panasonic — LiDAR Detection shelf log path (docker)
  # "${COREROBOT_DOCKER_LOG_CORE}"                      "corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*"  "<mtime>"
  # "${COREROBOT_DOCKER_LOG_DATA}/lidar_detection"      "detect_shelf_node-DetectShelf_<date:%Y%m%d%H%M%S>*<suffix:.dat>"         ""
  # "${COREROBOT_DOCKER_LOG_DATA}/lidar_detection"      "detect_shelf_<date:%Y%m%d%H%M%S>*<suffix:.pcd>"                          ""
  # "${COREROBOT_DOCKER_LOG_DATA}/lidar_detection/glog" "detect_shelf_node-DetectShelf-<date:%Y%m%d-%H%M%S>*"                     ""
  # "${COREROBOT_DOCKER_LOG_SLAM}"                      "coreslam_2D_<date:%s>*<suffix:.log>"                                     ""
  # "${COREROBOT_DOCKER_LOG_SLAM}/record"               "coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*<suffix:.rec>"                      ""
  # "${COREROBOT_DOCKER_STORAGE}"                       "node_config.yaml"                                                        ""
  # "${COREROBOT_DOCKER_STORAGE}"                       "shelf.ini"                                                               ""
  # "${COREROBOT_DOCKER_STORAGE}"                       "external_param.launch"                                                   ""
  # "${COREROBOT_DOCKER_STORAGE}"                       "run_config.yaml"                                                         ""

  # sys_log kernal_log
  # # 2D LiDAR SLAM log path (docker)
  "${COREROBOT_DOCKER_LOG_CORE}"        "corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*"  "<mtime>"
  "${COREROBOT_DOCKER_LOG_SLAM}"        "coreslam_2D_<date:%s>*<suffix:.log>"                                     ""
  "${COREROBOT_DOCKER_LOG_SLAM}/record" "coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*<suffix:.rec>"                      ""

  # # 2D LiDAR AvoidStop log path (docker)
  # "${COREROBOT_DOCKER_STORAGE}/mapfile/default"  "uimap.png"                                                              ""
  # "${COREROBOT_DOCKER_STORAGE}/mapfile/default"  "uimap.yaml"                                                             ""
  # "${COREROBOT_DOCKER_LOG}/AvoidStop_<date:%Y-%m-%d>"  "<date:%Y-%m-%d-%H.%M.%S>_*<suffix:_avoid.png>"                    ""
  # "${COREROBOT_DOCKER_LOG_CORE}"                 "corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*"  "<mtime>"
  # "${COREROBOT_DOCKER_LOG_SLAM}/record"          "coreslam_2D_<date:%Y-%m-%d-%H-%M-%S>*<suffix:.rec>"                      ""

  # # ASE Us — LiDAR Detection pallet log path
  # "${COREROBOT_LOG_DATA}/lidar_detection"                                          "detect_pallet_node-DetectPallet_<date:%Y%m%d%H%M%S>*<suffix:.dat>"  ""
  # "${COREROBOT_LOG_DATA}/lidar_detection"                                          "detect_pallet_node-DetectPallet_<date:%Y%m%d%H%M%S>*<suffix:.pcd>"  ""
  # "${COREROBOT_LOG_DATA}/lidar_detection/glog"                                     "detect_pallet_node-DetectPallet-<date:%Y%m%d-%H%M%S>*"              ""
  # "${COREROBOT_CORETRONIC_AMR_NAVI_INSTALL}/share/lidar_detection_pkg/config"      "pallet.ini"                                                        ""
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
declare FILE_TIME_TOLERANCE_MIN=30

# ==============================================================================
# Internal Variables (do not modify)
# ==============================================================================

declare -r VERSION="1.6.2"
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
      MSG_FILES_SELECTED='從 %d 個候選檔案中選取了 %d 個。'
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
      MSG_PROCESSING='[%d/%d] 處理中: %s :: %s'
      MSG_NO_FILES_FOUND='[%d/%d] 找不到檔案。'
      MSG_RESOLVED_PATH='[%d/%d] 解析結果: %s :: %s%s'
      MSG_FOUND_COPYING='[%d/%d] 找到 %d 個檔案，複製中...'
      MSG_STEP1='=== 步驟 1/5: 解析目標主機 ==='
      MSG_STEP2='=== 步驟 2/5: 驗證時間範圍 ==='
      MSG_STEP3_SSH='=== 步驟 3/5: 建立 SSH 連線 ==='
      MSG_STEP3_LOCAL='=== 步驟 3/5: 本機模式 (略過 SSH) ==='
      MSG_SUDO_REQUIRED='路徑 %s 不在 HOME 底下，需要 sudo 權限。'
      MSG_SUDO_FAILED='sudo 驗證失敗，路徑 %s 可能無法存取。'
      MSG_STEP4='=== 步驟 4/5: 收集 log 檔案 ==='
      MSG_STEP5_TRANSFER='=== 步驟 5/5: 傳輸檔案到本機 (%s) ==='
      MSG_STEP5_LOCAL='=== 步驟 5/5: 檔案已在本機收集完成 ==='
      MSG_OUTPUT_FOLDER='輸出資料夾: %s'
      MSG_SUCCESS='打包 log 完成。'
      MSG_DRY_RUN_BANNER='*** 模擬執行模式 — 不會複製或傳輸任何檔案 ***'
      MSG_DRY_RUN_RESOLVED='[模擬] 解析後路徑：%s'
      MSG_DRY_RUN_PATTERN='[模擬] 檔案樣式：  %s'
      MSG_DRY_RUN_DIR_NOT_FOUND='[模擬] 目錄不存在：%s'
      MSG_DRY_RUN_WOULD_COPY='[模擬] 將會複製 %d 個檔案：'
      MSG_DRY_RUN_TOTAL='[模擬] 總共會收集的檔案數量：%d'
      MSG_DRY_RUN_COMPLETE='*** 模擬執行完成 — 未做任何變更 ***'
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
      MSG_FILES_SELECTED='从 %d 个候选文件中选取了 %d 个。'
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
      MSG_PROCESSING='[%d/%d] 处理中: %s :: %s'
      MSG_NO_FILES_FOUND='[%d/%d] 未找到文件。'
      MSG_RESOLVED_PATH='[%d/%d] 解析结果: %s :: %s%s'
      MSG_FOUND_COPYING='[%d/%d] 找到 %d 个文件，复制中...'
      MSG_STEP1='=== 步骤 1/5: 解析目标主机 ==='
      MSG_STEP2='=== 步骤 2/5: 验证时间范围 ==='
      MSG_STEP3_SSH='=== 步骤 3/5: 建立 SSH 连接 ==='
      MSG_STEP3_LOCAL='=== 步骤 3/5: 本机模式 (跳过 SSH) ==='
      MSG_SUDO_REQUIRED='路径 %s 不在 HOME 底下，需要 sudo 权限。'
      MSG_SUDO_FAILED='sudo 验证失败，路径 %s 可能无法访问。'
      MSG_STEP4='=== 步骤 4/5: 收集 log 文件 ==='
      MSG_STEP5_TRANSFER='=== 步骤 5/5: 传输文件到本机 (%s) ==='
      MSG_STEP5_LOCAL='=== 步骤 5/5: 文件已在本机收集完成 ==='
      MSG_OUTPUT_FOLDER='输出文件夹: %s'
      MSG_SUCCESS='打包 log 完成。'
      MSG_DRY_RUN_BANNER='*** 模拟执行模式 — 不会复制或传输任何文件 ***'
      MSG_DRY_RUN_RESOLVED='[模拟] 解析后路径：%s'
      MSG_DRY_RUN_PATTERN='[模拟] 文件模式：  %s'
      MSG_DRY_RUN_DIR_NOT_FOUND='[模拟] 目录不存在：%s'
      MSG_DRY_RUN_WOULD_COPY='[模拟] 将会复制 %d 个文件：'
      MSG_DRY_RUN_TOTAL='[模拟] 总共会收集的文件数量：%d'
      MSG_DRY_RUN_COMPLETE='*** 模拟执行完成 — 未做任何变更 ***'
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
      MSG_FILES_SELECTED='%d 個の候補から %d 個のファイルを選択しました。'
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
      MSG_PROCESSING='[%d/%d] 処理中: %s :: %s'
      MSG_NO_FILES_FOUND='[%d/%d] ファイルが見つかりません。'
      MSG_RESOLVED_PATH='[%d/%d] 解決済み: %s :: %s%s'
      MSG_FOUND_COPYING='[%d/%d] %d 個のファイルが見つかりました。コピー中...'
      MSG_STEP1='=== ステップ 1/5: ターゲットホストの解決 ==='
      MSG_STEP2='=== ステップ 2/5: 時間範囲の検証 ==='
      MSG_STEP3_SSH='=== ステップ 3/5: SSH 接続の確立 ==='
      MSG_STEP3_LOCAL='=== ステップ 3/5: ローカルモード (SSH スキップ) ==='
      MSG_SUDO_REQUIRED='パス %s は HOME 外のため、sudo 権限が必要です。'
      MSG_SUDO_FAILED='sudo 認証に失敗しました。パス %s にアクセスできない可能性があります。'
      MSG_STEP4='=== ステップ 4/5: ログファイルの収集 ==='
      MSG_STEP5_TRANSFER='=== ステップ 5/5: ローカルへファイル転送中 (%s) ==='
      MSG_STEP5_LOCAL='=== ステップ 5/5: ローカルでファイル収集完了 ==='
      MSG_OUTPUT_FOLDER='出力フォルダ: %s'
      MSG_SUCCESS='ログのパッケージングが正常に完了しました。'
      MSG_DRY_RUN_BANNER='*** ドライランモード — ファイルのコピー・転送は行いません ***'
      MSG_DRY_RUN_RESOLVED='[ドライラン] 解決済みパス：%s'
      MSG_DRY_RUN_PATTERN='[ドライラン] ファイルパターン：%s'
      MSG_DRY_RUN_DIR_NOT_FOUND='[ドライラン] ディレクトリが見つかりません：%s'
      MSG_DRY_RUN_WOULD_COPY='[ドライラン] %d 個のファイルをコピー予定：'
      MSG_DRY_RUN_TOTAL='[ドライラン] 収集予定の合計ファイル数：%d'
      MSG_DRY_RUN_COMPLETE='*** ドライラン完了 — 変更は行われていません ***'
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
      MSG_PROCESSING='[%d/%d] Processing: %s :: %s'
      MSG_NO_FILES_FOUND='[%d/%d] No files found.'
      MSG_RESOLVED_PATH='[%d/%d] Resolved: %s :: %s%s'
      MSG_FOUND_COPYING='[%d/%d] Found %d files, copying...'
      MSG_STEP1='=== Step 1/5: Resolving target host ==='
      MSG_STEP2='=== Step 2/5: Validating time range ==='
      MSG_STEP3_SSH='=== Step 3/5: Establishing SSH connection ==='
      MSG_STEP3_LOCAL='=== Step 3/5: Local mode (skipping SSH) ==='
      MSG_SUDO_REQUIRED='Path %s is outside HOME, sudo permission required.'
      MSG_SUDO_FAILED='sudo authentication failed, path %s may be inaccessible.'
      MSG_STEP4='=== Step 4/5: Collecting log files ==='
      MSG_STEP5_TRANSFER='=== Step 5/5: Transferring files to local (%s) ==='
      MSG_STEP5_LOCAL='=== Step 5/5: Files collected locally ==='
      MSG_OUTPUT_FOLDER='Output folder: %s'
      MSG_SUCCESS='Packaging log completed successfully.'
      MSG_DRY_RUN_BANNER='*** DRY RUN MODE — no files will be copied or transferred ***'
      MSG_DRY_RUN_RESOLVED='[dry-run] Resolved path: %s'
      MSG_DRY_RUN_PATTERN='[dry-run] File pattern:  %s'
      MSG_DRY_RUN_DIR_NOT_FOUND='[dry-run] Directory not found: %s'
      MSG_DRY_RUN_WOULD_COPY='[dry-run] Would copy %d files:'
      MSG_DRY_RUN_TOTAL='[dry-run] Total files that would be collected: %d'
      MSG_DRY_RUN_COMPLETE='*** Dry run complete — no changes were made ***'
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

# Writes plain-text log entry to the log file (no-op if log file not yet initialized)
_log_to_file() {
  [[ -n "${_LOG_FD}" ]] && printf '%s\n' "$*" >&"${_LOG_FD}"
  return 0
}

# Opens the log file for writing. Call after SAVE_FOLDER is finalized.
# In remote mode, SAVE_FOLDER exists on the remote host but not locally.
# Create the local directory first so the log file can be written.
init_log_file() {
  LOG_FILE="${SAVE_FOLDER}/pack_log.log"
  mkdir -p "${SAVE_FOLDER}"
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
  echo "${MSG_HELP_DRY_RUN}"
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
# Sets:
#   REPLY: The formatted date string.
date_format() {
  local -r date="${1:?"${FUNCNAME[0]} need date."}"; shift
  local -r format="${1:?"${FUNCNAME[0]} need format."}"; shift

  log_verbose "${FUNCNAME[0]} input is: "
  log_verbose "  date: ${date}"
  log_verbose "  format: ${format}"

  if [[ ! "${date}" =~ ^[0-9]{6}-[0-9]{4}$ ]]; then
    log_error "$(printf "${MSG_INVALID_DATE_FORMAT}" "${date}")"
  fi

  local ymd hms
  ymd="20${date:0:2}-${date:2:2}-${date:4:2}"
  hms="${date:7:2}:${date:9:2}:00"

  if ! REPLY=$(date -d "${ymd} ${hms}" "+${format}"); then
    log_error "$(printf "${MSG_DATE_FORMAT_FAILED}" "${date}")"
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
    printf -v get_cmd 'printf "%%s" "${%s}"' "${str}"
  elif [[ "${type}" == "cmd" ]]; then
    get_cmd="${str}"
  else
    log_error "$(printf "${MSG_UNKNOWN_TOKEN_TYPE}" "${type}")"
  fi

  log_debug "Executing command: ${get_cmd}"

  if ! REPLY=$(execute_cmd "${get_cmd}"); then
    log_error "$(printf "${MSG_COMMAND_FAILED}" "${get_cmd}")"
  fi
  _TOKEN_CACHE["${cache_key}"]="${REPLY}"

  log_verbose "--------------------"
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
  [[ "${path}" != "${home_dir}"* ]] && return 0

  return 1
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
    log_error "$(printf "${MSG_FOLDER_CREATE_FAILED}" "${path}")"
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
      log_error "$(printf "${MSG_INVALID_INPUT}" "${input}")"
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

    if [[ "${time}" =~ ^[0-9]{6}-[0-9]{4}$ ]]; then
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
# Sets GET_LOG_TOOL to the first usable tool found.
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

# Handles path and pattern strings containing special tokens.
#
# This function takes a path and a pattern, finds all special tokens in the
# format `<...>`, and replaces them with their resolved values.
#
# Arguments:
#   path_str:    The directory path to process.
#   pattern_str: The file name pattern to process.
#
# Sets:
#   REPLY_PATH:   The resolved directory path.
#   REPLY_PREFIX: The resolved file name pattern (without suffix token).
#   REPLY_SUFFIX: The suffix filter (from <suffix:> token), or empty.
string_handler() {
  local path_str="${1:?"${FUNCNAME[0]} needs path argument."}"; shift
  local pattern_str="${1:?"${FUNCNAME[0]} needs pattern argument."}"; shift
  REPLY_SUFFIX=""

  log_debug "Original path: ${path_str}"
  log_debug "Original pattern: ${pattern_str}"

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
        log_debug "Date token process later: ${token}"
        date_tokens+=("${token}")
        str_ref="${str_ref//${token}/__DATE_TOKEN_${i}__}"
        (( i+=1 ))
        continue
      fi

      # normal case, replace directly
      log_debug "Processing token: ${token}"
      special_string_parser "${token:1:-1}"
      if [[ "${REPLY_TYPE}" == "suffix" ]]; then
        REPLY_SUFFIX="${REPLY_STR}"
        log_debug "Suffix set to: ${REPLY_SUFFIX}"
        str_ref="${str_ref//${token}/}"
        continue
      fi
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
# Sets:
#   REPLY_PATHS: Array of resolved paths (one per date when cross-date,
#                or single element when no date token in path).
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

  # Determine step size from format (daily for most formats)
  local step_sec=86400  # default: 1 day

  local -a paths=()
  local -A seen=()
  local epoch="${start_epoch}"
  while [[ "${epoch}" -le "${end_epoch}" ]]; do
    local resolved_date
    resolved_date=$(date -d "@${epoch}" "+${fmt}" 2>/dev/null) || break
    local resolved_path="${path//${token}/${resolved_date}}"
    if [[ -z "${seen["${resolved_path}"]+set}" ]]; then
      paths+=("${resolved_path}")
      seen["${resolved_path}"]=1
    fi
    epoch=$(( epoch + step_sec ))
  done

  # Also include END_TIME's date in case step missed it
  local end_date
  end_date=$(date -d "@${end_epoch}" "+${fmt}" 2>/dev/null) || true
  local end_path="${path//${token}/${end_date}}"
  if [[ -z "${seen["${end_path}"]+set}" ]]; then
    paths+=("${end_path}")
  fi

  REPLY_PATHS=("${paths[@]}")
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
  local use_mtime="${1:-false}"; shift || true
  local use_sudo="${1:-false}"; shift || true
  local sudo_prefix=""
  [[ "${use_sudo}" == "true" ]] && sudo_prefix="sudo "

  log_verbose "${FUNCNAME[0]} input: Path=${folder_path}, Prefix=${file_prefix}"

  local token="" format_position=""
  if [[ "${file_prefix}" =~ (<date:[^<>]*>) ]]; then
    token="${BASH_REMATCH[1]}"
    format_position="prefix"
    file_prefix="${file_prefix//${token}/*}"
  elif [[ "${file_suffix}" =~ (<date:[^<>]*>) ]]; then
    token="${BASH_REMATCH[1]}"
    format_position="suffix"
    file_suffix="${file_suffix//${token}/*}"
  fi
  log_debug "Date token position: ${format_position}, content: ${token}"

  local format=""
  if [[ -n "${token}" ]]; then
    special_string_parser "${token:1:-1}"
    format="${REPLY_STR}"
  fi

  # Combine prefix+suffix, collapse consecutive * into single *
  local name_pattern="${file_prefix}${file_suffix}"
  name_pattern="${name_pattern//\*\*/*}"

  local find_cmd
  printf -v find_cmd "%sfind -L %q -maxdepth 1 \\( -type f -o -type l \\) -name '%s' 2>/dev/null | sort" \
    "${sudo_prefix}" "${folder_path}" "${name_pattern}"

  # get file list
  local -a raw_files=()
  if ! mapfile -t raw_files < <(execute_cmd "${find_cmd}"); then
    REPLY_FILES=()
    return 0
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

  local s_idx=-1 e_idx=-1
  for i in "${!uniq_ts[@]}"; do
    if [[ $s_idx -eq -1 ]] && [[ "${uniq_ts[i]}" > "${formatted_start_ts}" || "${uniq_ts[i]}" == "${formatted_start_ts}" ]]; then
      s_idx=$i
    fi
    if [[ "${uniq_ts[i]}" < "${formatted_end_ts}" || "${uniq_ts[i]}" == "${formatted_end_ts}" ]]; then
      e_idx=$i
    fi
  done

  # [5] Check if any file falls strictly within the requested range
  local has_exact_match=false
  for ts in "${uniq_ts[@]}"; do
    if [[ ! "$ts" < "${formatted_start_ts}" && ! "$ts" > "${formatted_end_ts}" ]]; then
      has_exact_match=true
      break
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
    log_debug "Expanded Index Range: ${s_idx} to ${e_idx} (Values: ${final_start_val} ~ ${final_end_val})"

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

      local -a selected=()
      for i in "${!all_files[@]}"; do
        ts="${file_timestamps[i]}"
        local file_epoch
        if [[ "${format}" == "%s" ]]; then
          # Epoch format: timestamp IS the epoch
          file_epoch="${ts}"
        else
          # Date string format: parse YYYYMMDD... to epoch
          file_epoch=$(date -d "$(
            local y="${ts:0:4}" m="${ts:4:2}" d="${ts:6:2}"
            local rest="${ts:8}"
            local H="${rest:0:2}" M="${rest:2:2}" S="${rest:4:2}"
            printf '%s-%s-%s %s:%s:%s' "$y" "$m" "$d" "$H" "$M" "${S:-00}"
          )" '+%s' 2>/dev/null) || continue
        fi

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

  # [6] mtime fallback: check unselected files by modification time
  if [[ "${use_mtime}" == "true" && ${#raw_files[@]} -gt 0 ]]; then
    local mtime_start_epoch
    date_format "${start_time}" "%s"; mtime_start_epoch="${REPLY}"

    local -A selected_set=()
    local f
    for f in "${REPLY_FILES[@]+"${REPLY_FILES[@]}"}"; do
      selected_set["${f}"]=1
    done

    for f in "${raw_files[@]}"; do
      [[ -n "${selected_set["${f}"]+set}" ]] && continue

      local file_mtime
      file_mtime=$(execute_cmd "${sudo_prefix}stat -c %Y $(printf '%q' "${f}")") || continue
      # A file with mtime >= start means it was still being written during the range.
      # We don't check <= end because a continuously written log that spans past the
      # range end was clearly also active during the range.
      if [[ "${file_mtime}" -ge "${mtime_start_epoch}" ]]; then
        REPLY_FILES+=("${f}")
      fi
    done
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
save_script_data() {
  local -a string_array=(
    "Host: ${HOST}"
    "Time range: ${START_TIME} ~ ${END_TIME}"
    "Using tool: ${GET_LOG_TOOL}"
    "Saving logs to folder: ${SAVE_FOLDER}"
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
#   SAVE_FOLDER: The path of the folder to be removed.
file_cleaner() {
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
file_sender() {
  local -r tool="${GET_LOG_TOOL}"
  # Default: show overall transfer progress (--info=progress2)
  # Verbose: add per-file detail (-v --progress)
  # --partial: keep partially transferred files (resume on retry)
  # --timeout: rsync-level I/O timeout (complements SSH ServerAliveInterval)
  local -a rsync_flags=("-a" "-z" "--info=progress2" "--partial" "--timeout=60")
  local -a scp_flags=("-p" "-r")
  local sftp_progress="progress\n" sftp_output="/dev/stdout"

  # KCOV_EXCL_START — file_sender only runs in remote integration tests
  if [[ "${VERBOSE:-0}" -ge 1 ]]; then
    rsync_flags+=("-v" "--progress")
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

  # Check if folder size exceeds warning threshold
  if [[ "${TRANSFER_SIZE_WARN_MB:-0}" -gt 0 ]]; then
    local size_bytes
    size_bytes=$(execute_cmd "du -sb ${remote_esc} | awk '{print \$1}'")
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
  # KCOV_EXCL_STOP
}

# Dry-run variant of get_log: finds and lists files without copying.
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
    local use_mtime=false use_sudo=false
    [[ "${log_flags}" == *"<mtime>"* ]] && use_mtime=true
    [[ "${log_flags}" == *"<sudo>"* ]] && use_sudo=true
    (( ++idx ))

    log_info "$(printf "${MSG_PROCESSING}" "${idx}" "${total}" "${log_path}" "${log_pattern}")"
    string_handler "${log_path}" "${log_pattern}"
    resolve_path_dates
    local prefix="${REPLY_PREFIX}" suffix="${REPLY_SUFFIX}"

    local path_found=false
    local rpath=""
    for rpath in "${REPLY_PATHS[@]}"; do
      log_info "$(printf "${MSG_RESOLVED_PATH}" "${idx}" "${total}" "${rpath}" "${prefix}" "${suffix}")"

      if [[ -z "${rpath}" ]]; then
        log_warn "$(printf "${MSG_EMPTY_PATH}" "${idx}" "${total}")"
        continue
      fi

      log_info "$(printf "${MSG_DRY_RUN_RESOLVED}" "${rpath}")"
      log_info "$(printf "${MSG_DRY_RUN_PATTERN}" "${prefix}${suffix}")"

      if ! execute_cmd "test -d $(printf '%q' "${rpath}")"; then
        log_warn "$(printf "${MSG_DRY_RUN_DIR_NOT_FOUND}" "${rpath}")"
        continue
      fi

      file_finder "${rpath}" "${prefix}" "${suffix}" "${START_TIME}" "${END_TIME}" "${use_mtime}" "${use_sudo}"
      local -a files=("${REPLY_FILES[@]+"${REPLY_FILES[@]}"}")

      if [[ "${#files[@]}" -gt 0 ]]; then
        path_found=true
        log_info "$(printf "${MSG_DRY_RUN_WOULD_COPY}" "${#files[@]}")"
        local f
        for f in "${files[@]}"; do
          log_info "  ${f}"
        done
        (( grand_total += ${#files[@]} ))
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
get_log() {
  if (( ${#LOG_PATHS[@]} % 3 != 0 )); then
    log_warn "LOG_PATHS has ${#LOG_PATHS[@]} elements (not a multiple of 3). Check configuration."
  fi

  local log_path="" log_pattern="" log_flags=""
  local total=$(( ${#LOG_PATHS[@]} / 3 ))
  local idx=0
  local i

  # Pre-scan: check if any path needs sudo, authenticate once if so
  local _sudo_authenticated=false
  for (( i=0; i<${#LOG_PATHS[@]}; i+=3 )); do
    string_handler "${LOG_PATHS[i]}" "${LOG_PATHS[i+1]}"
    resolve_path_dates
    local rp=""
    for rp in "${REPLY_PATHS[@]}"; do
      if _needs_sudo "${rp}" "${LOG_PATHS[i+2]}"; then
        log_info "$(printf "${MSG_SUDO_REQUIRED}" "${rp}")"
        if execute_cmd "sudo -v"; then
          _sudo_authenticated=true
        else
          log_warn "$(printf "${MSG_SUDO_FAILED}" "${rp}")"
        fi
        break 2
      fi
    done
  done

  local _total_files_found=0
  for (( i=0; i<${#LOG_PATHS[@]}; i+=3 )); do
    log_path="${LOG_PATHS[i]}"
    log_pattern="${LOG_PATHS[i+1]}"
    log_flags="${LOG_PATHS[i+2]}"
    local use_mtime=false
    [[ "${log_flags}" == *"<mtime>"* ]] && use_mtime=true
    (( ++idx ))

    log_info "$(printf "${MSG_PROCESSING}" "${idx}" "${total}" "${log_path}" "${log_pattern}")"
    string_handler "${log_path}" "${log_pattern}"
    resolve_path_dates
    local prefix="${REPLY_PREFIX}" suffix="${REPLY_SUFFIX}"

    local -a all_found_files=()
    local rpath=""
    for rpath in "${REPLY_PATHS[@]}"; do
      # Auto-detect sudo based on path
      local use_sudo=false
      _needs_sudo "${rpath}" "${log_flags}" && use_sudo=true

      log_info "$(printf "${MSG_RESOLVED_PATH}" "${idx}" "${total}" "${rpath}" "${prefix}" "${suffix}")"

      if [[ -z "${rpath}" ]]; then
        log_warn "$(printf "${MSG_EMPTY_PATH}" "${idx}" "${total}")"
        continue
      fi

      file_finder "${rpath}" "${prefix}" "${suffix}" "${START_TIME}" "${END_TIME}" "${use_mtime}" "${use_sudo}"
      if [[ "${#REPLY_FILES[@]}" -gt 0 ]]; then
        all_found_files+=("${REPLY_FILES[@]}")
        _SUDO_PREFIX=""; [[ "${use_sudo}" == "true" ]] && _SUDO_PREFIX="sudo "
        file_copier "${rpath}" "${REPLY_FILES[@]}"
        _SUDO_PREFIX=""
      fi
    done

    if [[ "${#all_found_files[@]}" -eq 0 ]]; then
      log_warn "$(printf "${MSG_NO_FILES_FOUND}" "${idx}" "${total}")"
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
main() {
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

  log_info "${MSG_STEP4}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    get_log_dry_run
    log_info "${MSG_DRY_RUN_COMPLETE}"
  else
    folder_creator
    init_log_file

    # Trap only signals, not EXIT — preserve /tmp folder for debug after completion
    trap file_cleaner SIGINT SIGTERM

    save_script_data
    get_log

    if [[ "${HOST}" != "local" ]]; then
      log_info "$(printf "${MSG_STEP5_TRANSFER}" "${GET_LOG_TOOL}")"
      while ! file_sender; do
        local choice=""
        log_warn "${MSG_TRANSFER_CHOICE}"
        read -r choice </dev/tty 2>/dev/null || read -r choice # KCOV_EXCL_LINE
        case "${choice,,}" in
          k|keep)
            log_info "$(printf "${MSG_REMOTE_PRESERVED}" "${HOST}" "${SAVE_FOLDER}")"
            close_log_file; exit 1 ;;
          c|clean)
            file_cleaner
            close_log_file; exit 1 ;;
          *)  # retry (default: empty or 'r')
            log_info "[R]etry: restarting transfer..."
            continue ;;
        esac
      done
    else
      log_info "${MSG_STEP5_LOCAL}"
    fi

    log_info "$(printf "${MSG_OUTPUT_FOLDER}" "${SAVE_FOLDER}")"
    log_info "${MSG_SUCCESS}"
    close_log_file
  fi
}

# Allow sourcing without executing main.
# "return" succeeds when sourced but fails when executed directly.
# KCOV_EXCL_START
(return 0 2>/dev/null) || main "$@"
# KCOV_EXCL_STOP
