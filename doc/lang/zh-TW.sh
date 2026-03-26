#!/bin/bash
# 繁體中文訊息檔 for pack_log.sh

# --- 說明文字 ---
# shellcheck disable=SC2034
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

# --- 套件 / sudo ---
MSG_CHECKING_SUDO='正在檢查 sudo 權限。'
MSG_PKG_ALREADY_INSTALLED='套件 %s 已安裝。'
MSG_PKG_NOT_FOUND='找不到套件 %s，正在安裝...'
MSG_NO_SUDO_ACCESS='沒有 sudo 權限來安裝 %s。'
MSG_PKG_INSTALL_FAILED='安裝套件 %s 失敗。'

# --- 日期格式 ---
MSG_INVALID_DATE_FORMAT='無效的日期格式: %s'
MSG_DATE_FORMAT_FAILED='日期格式化失敗: %s'

# --- 遠端值 / token ---
MSG_UNKNOWN_TOKEN_TYPE='未知的類型: %s'
MSG_COMMAND_FAILED='指令執行失敗: %s'
MSG_INVALID_SPECIAL_STRING='無效的特殊字串格式: %s'
MSG_UNKNOWN_SPECIAL_STRING='未知的特殊字串類型: %s'
MSG_TOKEN_NUM_NO_HOST='Token %s 需搭配 -n（主機編號），使用 -u 或 -l 時會被忽略'

# --- 資料夾 ---
MSG_FOLDER_CREATE_FAILED='建立資料夾失敗: %s'
MSG_HOSTNAME_DATE_FAILED='無法從 %s 取得主機名稱/日期'

# --- 主機選擇 ---
MSG_HOST_USING_LOCAL='使用本機作為目標主機'
MSG_HOST_PROMPT='輸入 local、編號 (1-%d) 或 user@host: '
MSG_INVALID_INPUT='無效的輸入: %s'
MSG_HOST_NUMBER_RANGE='編號必須在 1 到 %d 之間'
MSG_INVALID_USERHOST='無效的 user@host 格式: %s'

# --- 時間處理 ---
MSG_TIME_PROMPT='輸入 %s (YYmmdd-HHMM): '
MSG_INVALID_TIME_FORMAT='無效的 %s 格式: %s'
MSG_START_BEFORE_END='起始時間 (%s) 必須早於結束時間 (%s)'

# --- SSH ---
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

# --- 工具檢查 ---
MSG_RSYNC_NOT_AVAILABLE='遠端主機上沒有 rsync，嘗試下一個工具...'
MSG_NO_TRANSFER_TOOLS='沒有可用的檔案傳輸工具 (%s)。'

# --- 檔案操作 ---
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
MSG_UNSUPPORTED_TOOL='不支援的檔案傳輸工具: %s'
MSG_TRANSFER_RETRY='%s 失敗 (第 %d/%d 次)，%d 秒後重試...'
MSG_TRANSFER_FAILED='%s 在 %d 次嘗試後失敗。'
MSG_REMOTE_PRESERVED='遠端資料夾已保留: %s:%s'
MSG_RETRIEVE_MANUALLY='請手動取回檔案，完成後請刪除遠端資料夾。'

# --- get_log ---
MSG_EMPTY_PATH='[%d/%d] 解析後路徑為空，跳過。'
MSG_PROCESSING='[%d/%d] 處理中: %s'
MSG_NO_FILES_FOUND='[%d/%d] 找不到檔案。'
MSG_FOUND_COPYING='[%d/%d] 找到 %d 個檔案，複製中...'

# --- 主要步驟 ---
MSG_STEP1='=== 步驟 1/5: 解析目標主機 ==='
MSG_STEP2='=== 步驟 2/5: 驗證時間範圍 ==='
MSG_STEP3_SSH='=== 步驟 3/5: 建立 SSH 連線 ==='
MSG_STEP3_LOCAL='=== 步驟 3/5: 本機模式 (略過 SSH) ==='
MSG_STEP4='=== 步驟 4/5: 收集 log 檔案 ==='
MSG_STEP5_TRANSFER='=== 步驟 5/5: 傳輸檔案到本機 (%s) ==='
MSG_STEP5_LOCAL='=== 步驟 5/5: 檔案已在本機收集完成 ==='
MSG_SUCCESS='打包 log 完成。'

# --- 模擬執行 ---
MSG_DRY_RUN_BANNER='*** 模擬執行模式 — 不會複製或傳輸任何檔案 ***'
MSG_DRY_RUN_RESOLVED='[模擬] 解析後路徑：%s'
MSG_DRY_RUN_PATTERN='[模擬] 檔案樣式：  %s'
MSG_DRY_RUN_DIR_NOT_FOUND='[模擬] 目錄不存在：%s'
MSG_DRY_RUN_WOULD_COPY='[模擬] 將會複製 %d 個檔案：'
MSG_DRY_RUN_TOTAL='[模擬] 總共會收集的檔案數量：%d'
MSG_DRY_RUN_COMPLETE='*** 模擬執行完成 — 未做任何變更 ***'
