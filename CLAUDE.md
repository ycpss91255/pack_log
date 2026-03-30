# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概述

`pack_log.sh` 是一個單檔 Bash 腳本（約 2090 行），用於透過 SSH 連線到遠端主機，依照指定時間範圍尋找 log 檔案，複製到遠端暫存資料夾後，再用 rsync/scp/sftp 傳回本機。支援 i18n（en/zh-TW/zh-CN/ja），所有翻譯內嵌於腳本中（無外部語言檔）。

## 執行方式

```bash
# 依主機編號（未指定則互動式選擇）
./pack_log.sh -n 1 -s 260101-0000 -e 260101-2359

# 直接指定 user@host
./pack_log.sh -u myuser@10.90.68.188 -s 260101-0000 -e 260101-2359

# 本機模式（不走 SSH）
./pack_log.sh -l -s 260101-0000 -e 260101-2359

# 詳細輸出：-v（debug）、--very-verbose（verbose）、--extra-verbose（set -x）

# Dry run：只列出檔案，不複製不傳輸
./pack_log.sh -n 1 -s 260101-0000 -e 260101-2359 --dry-run
```

## 測試

測試使用 [Bats](https://github.com/bats-core/bats-core)，透過 `bash_test_helper/` 子模組。CI 流程在 Docker 中執行 ShellCheck、Bats 測試與 Kcov 覆蓋率：

```bash
# 執行全部測試（需要 Docker + Docker Compose）
./ci.sh

# 只跑 unit test + ShellCheck + coverage
./ci.sh unit

# 只跑遠端整合測試
./ci.sh integration
```

### 跑單一測試檔案（本機需先安裝 bats + 相關 library）

```bash
bats test/test_option_parser.bats
```

### 跑特定測試（依名稱過濾）

```bash
bats test/test_option_parser.bats -f "parses -n flag"
```

測試檔案放在 `test/` 目錄下，副檔名為 `.bats`。測試輔助模組（`test/test_helper.bash`）會自動載入 bats-support、bats-assert、bats-file 和 bats-mock。

## 架構

腳本在 `main()` 中依序執行以下流程：

1. **`option_parser`** — 透過 `getopt` 解析命令列參數（含 `--lang`）
2. **`load_lang`** — 載入 i18n 翻譯（全部內嵌於腳本的 `case` 語句中）
3. **`host_handler`** — 解析目標主機（編號 → HOSTS 陣列查詢、user@host、或 "local"）
4. **`time_handler`** — 驗證起訖時間格式（`YYMMDD-HHMM`），確認 START < END
5. **`ssh_handler`** — 建立 SSH 連線，自動建立/複製金鑰（最多重試 3 次）
6. **`folder_creator`** — 建立暫存資料夾（`<script_name>_<host_label>_<YYMMDD-HHMMSS>`，`-n` 用 HOSTS 顯示名，其他用 hostname）
7. **`init_log_file`** — 開啟 log 檔案寫入（`pack_log.log`）
8. **`get_log`** — 遍歷 `LOG_PATHS`，解析特殊 token，依時間範圍篩選檔案並複製到暫存資料夾
9. **`file_sender`** — 透過 rsync/scp/sftp 將暫存資料夾傳回本機（失敗後互動式選擇 retry/keep/clean）

### LOG_PATHS 特殊 Token 系統

Log 路徑字串支援在執行時對遠端主機解析的 token：
- `<env:VAR>` — 遠端環境變數
- `<cmd:command>` — 遠端 shell 指令輸出
- `<date:format>` — 時間範圍篩選用的日期格式（如 `<date:%Y%m%d-%H%M%S>`）
- `<suffix:ext>` — 副檔名篩選

處理鏈：`string_handler` → `special_string_parser` → `get_remote_value`（處理 env/cmd token）

### 指令執行模型

所有遠端指令都透過 `execute_cmd()` 執行，將指令字串以 pipe 方式送入 `bash -ls`（本機或 SSH），藉此避免 shell 跳脫問題。`execute_cmd_from_array()` 則處理以 null 分隔的陣列 pipe，用於檔案操作。

## 設定

`pack_log.sh` 頂部的 `HOSTS` 和 `LOG_PATHS` 陣列是主要設定點，目前寫死為特定部署站點（Panasonic AMR 車隊）。如需變更目標主機或 log 路徑，直接編輯這兩個陣列。

可調參數也在腳本頂部：`SSH_KEY`、`SSH_TIMEOUT`、`TRANSFER_MAX_RETRIES`、`TRANSFER_RETRY_DELAY`、`TRANSFER_SIZE_WARN_MB`、`FILE_TIME_TOLERANCE_MIN`。

## 開發流程

本專案採用 TDD（Test-Driven Development）：
1. **先寫測試**：在對應的 `test/test_*.bats` 中新增或修改測試案例
2. **確認測試失敗**：執行 `bats test/test_xxx.bats` 確認新測試為紅燈
3. **實作功能**：修改 `pack_log.sh` 使測試通過
4. **執行完整測試**：`./ci.sh unit` 確認所有測試通過且 ShellCheck 合規

### 每次改動後的檢查清單

1. **測試**：`bats test/` 本地通過 + `./ci.sh unit` CI 通過
2. **文件更新**：README（4 語言）、CLAUDE.md、TEST.md（4 語言）的測試數量、行數、功能描述是否同步
3. **過時檔案**：確認沒有引用已刪除的檔案（如舊的 `doc/lang/`）或過時的格式描述

## 重要慣例

- 腳本使用 `set -euo pipefail`，所有錯誤皆為致命錯誤
- 函式使用 REPLY 慣例作為輸出（`REPLY`, `REPLY_TYPE`, `REPLY_STR` 等）
- SSH 金鑰路徑固定為 `~/.ssh/get_log`
- CI 中強制執行 ShellCheck（`shellcheck -x -S error pack_log.sh`）
- Source guard 使腳本可被 source 而不執行 `main()`：`(return 0 2>/dev/null) || main "$@"`
- 測試中 `declare` 的變數（HOSTS、LOG_PATHS 等）在 source 時會變成 local scope，需在每個 test 的 `setup()` 中重新初始化
- 覆蓋率排除標記：`# KCOV_EXCL_START` / `# KCOV_EXCL_STOP`（區塊排除）、`# KCOV_EXCL_LINE`（單行排除）——用於部署特定設定和 runtime-only 分支
