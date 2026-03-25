# Pack Log [![Test Status](https://github.com/ycpss91255/pack_log/workflows/Main%20CI/CD%20Pipeline/badge.svg)](https://github.com/ycpss91255/pack_log/actions) [![Code Coverage](https://codecov.io/gh/ycpss91255/pack_log/branch/main/graph/badge.svg)](https://codecov.io/gh/ycpss91255/pack_log)

![Language](https://img.shields.io/badge/Language-Bash-blue?style=flat-square)
![Testing](https://img.shields.io/badge/Testing-Bats-orange?style=flat-square)
![ShellCheck](https://img.shields.io/badge/ShellCheck-Compliant-brightgreen?style=flat-square)

> **語言**: [English](../README.md) | 繁體中文 | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

> **TL;DR** — 單檔 Bash 腳本，透過 SSH 連線到遠端主機，依時間範圍尋找 log 檔案，再用 rsync/scp/sftp 傳回本機。100% 測試覆蓋率（Bats + Kcov）。
>
> ```bash
> ./pack_log.sh -n 1 -s 20260115-000000 -e 20260115-235959   # 依主機編號
> ./pack_log.sh -u myuser@10.90.68.188 -s ... -e ...          # 直接指定 user@host
> ./pack_log.sh -l -s ... -e ...                               # 本機模式
> ```

專為機器人車隊部署設計的 log 收集工具。自動處理 SSH 連線建立、支援動態 token 解析的時間範圍 log 搜尋，以及檔案傳輸回本機。

## 功能特點

- **多主機支援**：預設主機列表互動式選擇，或直接輸入 `user@host`。
- **智慧 Log 搜尋**：Token 系統支援動態路徑解析 — 環境變數（`<env:VAR>`）、Shell 指令（`<cmd:command>`）、日期格式（`<date:%Y%m%d>`）、副檔名篩選（`<suffix:.ext>`）。
- **時間範圍篩選**：在指定時間窗口內搜尋 log 檔案，自動擴展邊界確保不遺漏。
- **自動 SSH 金鑰管理**：自動建立 SSH 金鑰、複製到遠端主機、處理 host key 更新。
- **彈性傳輸方式**：支援 rsync、scp、sftp，自動偵測可用工具並依序嘗試。
- **本機模式**：不走 SSH，直接在本機收集 log。
- **i18n 多語言支援**：英文、繁體中文、簡體中文、日文，透過 `--lang` 或 `$LANG` 切換。
- **Log 檔案輸出**：所有操作記錄寫入 `pack_log.log`。
- **傳輸重試與保留**：失敗最多重試 3 次，最終失敗保留遠端資料夾。
- **100% 測試覆蓋率**：268 個測試，涵蓋單元測試、本機整合測試、遠端整合測試。

## 快速開始

### 基本使用

```bash
# 互動式選擇主機
./pack_log.sh -s 20260115-000000 -e 20260115-235959

# 依主機編號（HOSTS 陣列）
./pack_log.sh -n 1 -s 20260115-000000 -e 20260115-235959

# 直接指定 user@host
./pack_log.sh -u myuser@10.90.68.188 -s 20260115-000000 -e 20260115-235959

# 本機模式（不走 SSH）
./pack_log.sh -l -s 20260115-000000 -e 20260115-235959

# 自訂輸出資料夾 + 詳細輸出
./pack_log.sh -n 1 -s 20260115-000000 -e 20260115-235959 -o /tmp/my_logs -v
```

### 命令列選項

| 選項 | 說明 |
|------|------|
| `-n, --number` | 主機編號（對應 `HOSTS` 陣列） |
| `-u, --userhost <user@host>` | 直接指定 SSH 目標 |
| `-l, --local` | 本機模式（不走 SSH） |
| `-s, --start <YYYYmmdd-HHMMSS>` | 起始時間 |
| `-e, --end <YYYYmmdd-HHMMSS>` | 結束時間 |
| `-o, --output <path>` | 輸出資料夾路徑（預設：`log_pack`） |
| `-v, --verbose` | 啟用詳細輸出 |
| `--very-verbose` | 啟用 debug 輸出 |
| `--extra-verbose` | 啟用追蹤輸出（`set -x`） |
| `--lang <code>` | 語言：`en`、`zh-TW`、`zh-CN`、`ja` |
| `-h, --help` | 顯示說明 |
| `--version` | 顯示版本 |

## 架構

### 執行流程

```mermaid
graph LR
    A["pack_log.sh\nmain()"]:::entry

    A --> B["option_parser\ngetopt 解析命令列"]:::step
    B --> C["host_handler\n解析目標主機"]:::step
    C --> D["time_handler\n驗證時間範圍"]:::step
    D --> E{"HOST == local?"}:::decision

    E -->|否| F["ssh_handler\nSSH 金鑰 + 連線"]:::step
    F --> G["get_tools_checker\nrsync / scp / sftp"]:::step
    G --> H["folder_creator"]:::step

    E -->|是| H

    H --> I["get_log\n搜尋 + 複製檔案"]:::step
    I --> J{"HOST == local?"}:::decision

    J -->|否| K["file_sender\n傳輸回本機"]:::step
    K --> L["完成"]:::output
    J -->|是| L

    classDef entry fill:#1a5276,color:#fff,stroke:#2980b9
    classDef step fill:#8B6914,color:#fff,stroke:#c8960c
    classDef decision fill:#6c3483,color:#fff,stroke:#8e44ad
    classDef output fill:#1e8449,color:#fff,stroke:#27ae60
```

### LOG_PATHS Token 系統

Log 路徑支援在執行時對遠端主機動態解析的 token：

| Token | 說明 | 範例 |
|-------|------|------|
| `<env:VAR>` | 遠端環境變數 | `<env:HOME>/logs` |
| `<cmd:command>` | 遠端 shell 指令輸出 | `<cmd:hostname>` |
| `<date:format>` | 時間範圍篩選用的日期格式 | `<date:%Y%m%d-%H%M%S>` |
| `<suffix:ext>` | 副檔名篩選 | `<suffix:.pcd>` |

**處理鏈**：`string_handler` → `special_string_parser` → `get_remote_value`

**LOG_PATHS 範例**：
```bash
'<env:HOME>/ros-docker/AMR/myuser/log_core::corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*'
```

### 指令執行模型

所有遠端指令都透過 `execute_cmd()` 執行，將指令字串以 pipe 方式送入 `bash -ls`（本機或 SSH），藉此避免 shell 跳脫問題。`execute_cmd_from_array()` 則處理以 null 分隔的陣列 pipe，用於檔案操作。

## 設定

編輯 `pack_log.sh` 頂部的 `HOSTS` 和 `LOG_PATHS` 陣列：

```bash
# 目標主機: "顯示名稱::user@host"
declare -a HOSTS=(
  "server01::myuser@10.90.68.188"
  "server02::myuser@10.90.68.191"
)

# Log 路徑: "<路徑>::<檔案樣式>"
declare -a LOG_PATHS=(
  '<env:HOME>/logs::app_<date:%Y%m%d%H%M%S>*<suffix:.log>'
  '<env:HOME>/config::node_config.yaml'
)
```

## 專案目錄結構

```text
.
├── pack_log.sh                          # 主腳本（約 1340 行）
├── ci.sh                                # CI 入口（unit / integration / all）
├── docker-compose.yaml                  # Docker 服務（ci + sshd + integration）
├── .codecov.yaml                        # Codecov 設定
├── .gitignore
│
├── .github/workflows/
│   ├── main.yaml                        # CI 入口 workflow
│   └── test-worker.yaml                 # 測試 jobs（unit + integration）
│
├── test/
│   ├── test_helper.bash                 # 共用 bats 測試 helper
│   ├── test_log_functions.bats          # 日誌函式測試 (20)
│   ├── test_support_functions.bats      # 輔助函式測試 (37)
│   ├── test_option_parser.bats          # 選項解析測試 (44)
│   ├── test_host_handler.bats           # 主機選擇測試 (22)
│   ├── test_string_handler.bats         # 字串/Token 處理測試 (27)
│   ├── test_file_finder.bats            # 檔案搜尋測試 (20)
│   ├── test_file_ops.bats              # 檔案操作測試 (31)
│   ├── test_ssh_handler.bats            # SSH 處理測試 (13)
│   ├── test_main.bats                   # Main 流程測試 (17)
│   ├── test_integration_local.bats      # 本機整合測試 (13)
│   ├── Dockerfile.sshd                  # 遠端測試用 SSH 伺服器
│   ├── setup_remote_logs.sh             # 遠端測試資料建立腳本
│   ├── lib/bats-mock                    # Bats mock 函式庫（symlink）
│   └── integration/
│       ├── test_helper.bash             # 遠端測試 helper
│       └── test_remote.bats             # 遠端整合測試 (24)
│
├── doc/
│   ├── lang/                            # i18n 訊息檔
│   │   ├── en.sh                        # 英文（預設）
│   │   ├── zh-TW.sh                     # 繁體中文
│   │   ├── zh-CN.sh                     # 簡體中文
│   │   └── ja.sh                        # 日文
│   ├── README.zh-TW.md                  # 繁體中文 README
│   ├── README.zh-CN.md                  # 簡體中文 README
│   └── README.ja.md                     # 日文 README
│
└── bash_test_helper/                    # 參考架構子模組
```

## 測試

### 測試總覽

| 類別 | 測試數量 | 說明 |
|------|------:|------|
| 單元測試 | 231 | 個別函式測試 |
| 本機整合測試 | 13 | 完整 `main()` 本機模式流程 |
| 遠端整合測試 | 24 | 完整流程 + 真實 SSH 連線至 Docker sshd |
| **合計** | **268** | **100% 程式碼覆蓋率** |

### 執行測試

```bash
# 全部測試（需要 Docker）
./ci.sh

# 只跑單元測試 + ShellCheck + 覆蓋率
./ci.sh unit

# 只跑遠端整合測試
./ci.sh integration
```

### CI 流程

```mermaid
graph LR
    S["ci.sh unit"]:::entry --> SC["ShellCheck\n靜態分析 pack_log.sh"]:::step
    SC --> BT["Bats + Kcov\n244 個測試 + 覆蓋率"]:::step
    BT --> CC["Codecov\n上傳報告"]:::step

    S2["ci.sh integration"]:::entry --> SSHD["啟動 sshd\nDocker 容器"]:::step
    SSHD --> KEY["SSH 金鑰設定\n產生 + 複製"]:::step
    KEY --> DATA["建立測試資料\n遠端 log 檔案"]:::step
    DATA --> IT["Bats\n24 個遠端測試"]:::step

    classDef entry fill:#1a5276,color:#fff,stroke:#2980b9
    classDef step fill:#8B6914,color:#fff,stroke:#c8960c
```

### 遠端整合測試架構

```text
┌───────────────────────┐      SSH (port 22)      ┌───────────────────────┐
│  integration 容器     │ ◄──────────────────────► │      sshd 容器        │
│  (kcov/kcov)          │                          │    (ubuntu:22.04)     │
│                       │                          │                       │
│  • bats 測試執行器    │                          │  • openssh-server     │
│  • openssh-client     │                          │  • rsync              │
│  • rsync / sshpass    │                          │  • testuser + 金鑰   │
│  • pack_log.sh        │                          │  • 預建立的 log 檔案  │
└───────────────────────┘                          └───────────────────────┘
```

## 依賴

本機執行 CI 需要：
- **Docker** + **Docker Compose**

CI 容器會自動安裝：
- **Bats**（core + assert + file + support）：測試框架
- **ShellCheck**：靜態分析工具
- **Kcov**：覆蓋率報告產生器
- **openssh-client / rsync / sshpass**：SSH 和檔案傳輸工具

## 重要慣例

- 腳本使用 `set -euo pipefail`，所有錯誤皆為致命錯誤
- 函式使用 REPLY 慣例作為輸出（`REPLY`, `REPLY_TYPE`, `REPLY_STR` 等）
- SSH 金鑰路徑固定為 `~/.ssh/get_log`
- CI 中強制執行 ShellCheck 合規檢查（`-S error` 等級）
- 使用 `BASH_SOURCE` 守衛模式確保可測試性：
  ```bash
  if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
  fi
  ```
