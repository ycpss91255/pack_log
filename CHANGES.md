# pack_log.sh 變更與測試架構說明

## 目錄

- [pack\_log.sh Bug 修正](#packlogsh-bug-修正)
- [測試架構總覽](#測試架構總覽)
- [單元測試（Unit Tests）](#單元測試unit-tests)
- [本機整合測試（Local Integration Tests）](#本機整合測試local-integration-tests)
- [遠端整合測試（Remote Integration Tests）](#遠端整合測試remote-integration-tests)
- [CI/CD 架構](#cicd-架構)
- [覆蓋率機制](#覆蓋率機制)
- [專案目錄結構](#專案目錄結構)
- [執行方式](#執行方式)

---

## pack_log.sh Bug 修正

### 1. Help 文字格式與實際驗證不符

**檔案**: `pack_log.sh:169-170`

```
修正前: -s, --start <yymmdd-HHMM>     Start time (e.g. 260101-0000)
修正後: -s, --start <YYYYmmdd-HHMMSS>  Start time (e.g. 20260101-000000)
```

**原因**: `time_handler` 裡的正則驗證是 `^[0-9]{8}-[0-9]{6}$`（即 `YYYYmmdd-HHMMSS`，共 15 字元），但 help 顯示的格式是 `yymmdd-HHMM`（只有 11 字元），會誤導使用者輸入錯誤格式。

### 2. string_handler log 順序錯誤

**檔案**: `pack_log.sh:797-798`

```bash
# 修正前（先 log 再賦值，顯示的是舊值）
log_debug "Suffix set to: ${sh_suffix_ref}"
sh_suffix_ref="${string}"

# 修正後（先賦值再 log，顯示正確的新值）
sh_suffix_ref="${string}"
log_debug "Suffix set to: ${sh_suffix_ref}"
```

**原因**: debug log 寫著「Suffix set to」但印出的是賦值前的舊值，在除錯時會產生誤導。

### 3. file_copier verbose 判斷永遠為 true

**檔案**: `pack_log.sh:1079`

```bash
# 修正前（VERBOSE=0 時 "0" 是非空字串，條件永遠成立）
if [[ -n "${VERBOSE-}" ]]; then

# 修正後（正確判斷 verbose 等級）
if [[ "${VERBOSE:-0}" -ge 1 ]]; then
```

**原因**: `VERBOSE` 初始值是 `0`，而 `-n "0"` 為 true（非空字串），導致 `cp -v` 永遠被加入，即使使用者沒有開啟 verbose 模式。

---

## 測試架構總覽

```
測試總數: 260 個
├── 單元測試:       223 個  (test/test_*.bats)
├── 本機整合測試:    13 個  (test/test_integration_local.bats)
└── 遠端整合測試:    24 個  (test/integration/test_remote.bats)

覆蓋率: 100% (457/457 行)
```

---

## 單元測試（Unit Tests）

針對 `pack_log.sh` 中的每個函式進行獨立測試。

| 測試檔案 | 測試對象 | 測試數量 |
|----------|---------|---------|
| `test_log_functions.bats` | `log_verbose`, `log_debug`, `log_info`, `log_warn`, `log_error`, `print_help` | 11 |
| `test_support_functions.bats` | `have_sudo_access`, `pkg_install_handler`, `date_format`, `execute_cmd`, `get_remote_value`, `create_folder`, `execute_cmd_from_array` | 31 |
| `test_option_parser.bats` | `option_parser`, `time_handler` 所有 flag 與分支 | 36 |
| `test_host_handler.bats` | `host_handler` 本地/數字/user@host/互動模式 | 22 |
| `test_string_handler.bats` | `special_string_parser`, `string_handler` 所有 token 類型 | 28 |
| `test_file_finder.bats` | `file_finder` 日期篩選、邊界擴展、各種格式 | 20 |
| `test_file_ops.bats` | `folder_creator`, `save_script_data`, `file_cleaner`, `file_copier`, `file_sender`, `get_tools_checker`, `get_log` | 28 |
| `test_ssh_handler.bats` | `ssh_handler` SSH 金鑰建立、連線重試、錯誤處理 | 13 |
| `test_main.bats` | `main()` 整體流程、help、參數、local/remote 模式 | 21 |

### 關鍵技術細節

- **bats `run` 與 nameref**：使用 `local -n`（nameref）的函式無法用 `run` 測試（subshell 無法回寫變數），需直接呼叫函式
- **`declare` 變數作用域**：`pack_log.sh` 在 bats `setup()` 中被 source 時，`declare` 建立的是 local 變數，函式返回後即消失。需要在每個測試的 `setup()` 中重新初始化 `HOSTS`、`SSH_OPTS` 等陣列
- **Docker root 環境**：CI 容器以 root 執行，`EUID=0` 使 `have_sudo_access()` 永遠在第一行 return，部分錯誤路徑無法被測試觸及

---

## 本機整合測試（Local Integration Tests）

**檔案**: `test/test_integration_local.bats`

測試 `main()` 在 local 模式下的完整管線，使用臨時目錄模擬真實的 log 目錄結構。

| 測試場景 | 說明 |
|---------|------|
| `<env:VAR>` token 解析 | 設定 `FAKE_HOME` 環境變數，驗證路徑正確解析 |
| `<cmd:command>` token 解析 | 使用 `<cmd:hostname>` 驗證命令替換 |
| `<date:%Y%m%d%H%M%S>` 篩選 | 建立跨日期檔案，驗證時間範圍篩選 |
| `<date:%s>` epoch 格式 | 測試 epoch 時間戳格式的檔案篩選 |
| `<suffix:ext>` 過濾 | 驗證只複製指定副檔名的檔案 |
| 混合 LOG_PATHS | 同時包含設定檔（無日期 token）和日期型 log |
| 無匹配檔案 | 時間範圍內沒有檔案，驗證警告訊息 |
| 輸出資料夾結構 | 驗證資料夾名稱包含 hostname 和日期 |
| script.log 內容 | 驗證使用者輸入摘要寫入 script.log |
| 檔案內容完整性 | 驗證複製後的檔案內容與原始檔案一致 |
| Verbose 模式 | 驗證 `-v` 輸出 debug 訊息 |
| 空目錄處理 | 空資料夾不報錯、只警告 |
| date token 在 suffix 位置 | `<date:>` 出現在 `::` 後面的 suffix 部分 |

### 測試資料結構

```
$BATS_TEST_TMPDIR/fake_home/ros-docker/AMR/myuser/
├── log_core/
│   ├── corenavi_auto.<hostname>.<user>.log.INFO.20260115-100000.1
│   ├── corenavi_auto.<hostname>.<user>.log.INFO.20260115-140000.2
│   └── corenavi_auto.<hostname>.<user>.log.INFO.20260116-080000.3
├── log_data/lidar_detection/
│   ├── detect_shelf_node-DetectShelf_20260115100000_001.dat
│   ├── detect_shelf_node-DetectShelf_20260115160000_002.dat
│   ├── detect_shelf_node-DetectShelf_20260116120000_003.dat
│   ├── detect_shelf_20260115100000_001.pcd
│   └── detect_shelf_20260115160000_002.pcd
├── log_slam/
│   ├── coreslam_2D_<epoch_in_range>.log
│   └── coreslam_2D_<epoch_out_range>.log
└── core_storage/
    ├── node_config.yaml
    └── shelf.ini
```

---

## 遠端整合測試（Remote Integration Tests）

**檔案**: `test/integration/test_remote.bats`

測試 `main()` 在 remote 模式下的完整管線，使用真實的 SSH 連線到 Docker sshd 容器。

### Docker 架構

```
┌─────────────────────────┐      SSH       ┌─────────────────────────┐
│   integration 容器      │ ────────────── │      sshd 容器          │
│   (kcov/kcov image)     │                │   (ubuntu:22.04)        │
│                         │                │                         │
│  - bats 測試執行        │                │  - openssh-server       │
│  - openssh-client       │                │  - rsync                │
│  - rsync                │                │  - testuser (密碼+金鑰) │
│  - sshpass (初始設定)   │                │  - 預建立的 log 檔案    │
└─────────────────────────┘                └─────────────────────────┘
```

### SSH 金鑰設定流程

1. integration 容器啟動時用 `ssh-keygen` 產生 ed25519 金鑰
2. 用 `sshpass` + `ssh-copy-id` 把公鑰複製到 sshd 容器
3. 驗證 key-based auth 可用
4. 透過 SSH 執行 `setup_remote_logs.sh` 在遠端建立測試資料
5. 執行 bats 測試

### 測試場景

| 測試場景 | 說明 |
|---------|------|
| SSH 連線 | 基本 `execute_cmd` 連線驗證 |
| 遠端命令執行 | `hostname`、環境變數讀取 |
| rsync 完整流程 | config 檔 + 日期篩選檔案的 rsync 傳輸 |
| scp 完整流程 | 強制使用 scp 傳輸 |
| sftp 完整流程 | 強制使用 sftp 傳輸 |
| `<cmd:hostname>` 遠端解析 | token 在遠端主機上解析（非本機） |
| 混合 LOG_PATHS | config + 日期型 + suffix 混合 |
| 無匹配檔案 | 遠端時間範圍外的處理 |
| EXIT trap 清理 | 驗證遠端暫存資料夾被自動刪除 |
| script.log 傳輸 | 驗證 script.log 存在於本機輸出 |
| 檔案內容完整性 | 傳輸後的檔案內容正確 |
| suffix 過濾 | 遠端只取 .pcd 不取 .dat |

### 相關檔案

| 檔案 | 說明 |
|------|------|
| `test/Dockerfile.sshd` | SSH 伺服器 Docker image（ubuntu:22.04 + openssh-server + rsync） |
| `test/setup_remote_logs.sh` | 在遠端主機建立測試用 log 檔案的腳本 |
| `test/integration/test_helper.bash` | 遠端測試的 bats helper（載入函式庫、設定 SSH 環境變數） |
| `docker-compose.integration.yaml` | 編排 sshd + integration 兩個容器 |
| `ci-integration.sh` | 執行遠端整合測試的入口腳本 |

---

## CI/CD 架構

### GitHub Actions 工作流程

```
.github/workflows/main.yaml
  └── 呼叫 test-worker.yaml
        ├── unit-test job
        │   ├── checkout (含 submodules)
        │   ├── 執行 ci.sh (ShellCheck + bats + kcov)
        │   ├── 顯示覆蓋率摘要
        │   ├── 上傳覆蓋率報告 (artifact)
        │   └── 上傳到 Codecov
        │
        └── integration-test job
            ├── checkout (含 submodules)
            └── 執行 ci-integration.sh (sshd + bats)
```

### Docker Compose 服務

| 檔案 | 服務 | 用途 |
|------|------|------|
| `docker-compose.yaml` | `ci` | 單元測試 + 本機整合測試 + ShellCheck + kcov 覆蓋率 |
| `docker-compose.integration.yaml` | `sshd` + `integration` | 遠端整合測試 |

---

## 覆蓋率機制

使用 [kcov](https://github.com/SimonKagworktrom/kcov) 追蹤 bash 腳本覆蓋率。

### kcov 排除標記

kcov 無法測量某些 bash 語法行（陣列字面值、多行命令替換等），需要用排除標記：

```bash
# 區塊排除
# KCOV_EXCL_START
declare -a HOSTS=(
  "pana01::myuser@10.90.68.188"
  ...
)
# KCOV_EXCL_STOP

# 單行排除
log_error "No sudo access" # KCOV_EXCL_LINE
```

### docker-compose.yaml 中的 kcov 設定

```bash
kcov --include-path=./pack_log.sh \
     --exclude-region=KCOV_EXCL_START:KCOV_EXCL_STOP \
     --exclude-line=KCOV_EXCL_LINE \
     ./coverage \
     bats test/
```

### 排除的行類型

| 類型 | 原因 |
|------|------|
| 陣列字面值行（`HOSTS`, `LOG_PATHS`, `SSH_OPTS`, `string_array` 等） | kcov 無法對陣列元素行產生 `possible_hits` |
| Docker root 環境下不可達的錯誤路徑 | `EUID=0` 使 `have_sudo_access` 永遠在第一行 return |
| 只能透過 `run bash -c` 子進程測試的行 | kcov 不追蹤獨立子進程的執行 |
| 多行命令替換的接續行 | kcov 無法正確插入 debug trap |

---

## 專案目錄結構

```
pack_log/
├── pack_log.sh                          # 主腳本
├── ci.sh                                # 單元測試 + 覆蓋率執行腳本
├── ci-integration.sh                    # 遠端整合測試執行腳本
├── docker-compose.yaml                  # 單元測試 Docker 編排
├── docker-compose.integration.yaml      # 遠端整合測試 Docker 編排
├── CLAUDE.md                            # Claude Code 指引
├── CHANGES.md                           # 本文件
├── .codecov.yaml                        # Codecov 設定
├── .gitignore
│
├── .github/workflows/
│   ├── main.yaml                        # CI 入口
│   └── test-worker.yaml                 # 測試 worker（unit + integration jobs）
│
├── test/
│   ├── test_helper.bash                 # bats 共用 helper
│   ├── test_log_functions.bats          # 日誌函式測試
│   ├── test_support_functions.bats      # 輔助函式測試
│   ├── test_option_parser.bats          # 選項解析測試
│   ├── test_host_handler.bats           # 主機選擇測試
│   ├── test_string_handler.bats         # 字串處理測試
│   ├── test_file_finder.bats            # 檔案搜尋測試
│   ├── test_file_ops.bats              # 檔案操作測試
│   ├── test_ssh_handler.bats            # SSH 處理測試
│   ├── test_main.bats                   # main() 流程測試
│   ├── test_integration_local.bats      # 本機整合測試
│   ├── Dockerfile.sshd                  # SSH 測試伺服器
│   ├── setup_remote_logs.sh             # 遠端測試資料建立
│   ├── lib/
│   │   └── bats-mock -> ../../bash_test_helper/test/lib/bats-mock
│   └── integration/
│       ├── test_helper.bash             # 遠端測試 helper
│       └── test_remote.bats             # 遠端整合測試
│
└── bash_test_helper/                    # 子模組（參考架構）
```

---

## 執行方式

```bash
# 單元測試 + 本機整合測試 + ShellCheck + 覆蓋率
bash ci.sh
# 覆蓋率報告: coverage/index.html

# 遠端整合測試（需要 Docker）
bash ci-integration.sh

# 只跑特定測試檔
docker compose run --rm ci bash -c \
  "apt-get update && apt-get install -y bats bats-support bats-assert bats-file && \
   bats test/test_file_finder.bats"
```
