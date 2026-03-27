# Pack Log [![Test Status](https://github.com/ycpss91255/pack_log/workflows/Main%20CI/CD%20Pipeline/badge.svg)](https://github.com/ycpss91255/pack_log/actions) [![Code Coverage](https://codecov.io/gh/ycpss91255/pack_log/branch/main/graph/badge.svg)](https://codecov.io/gh/ycpss91255/pack_log)

![Language](https://img.shields.io/badge/Language-Bash-blue?style=flat-square)
![Testing](https://img.shields.io/badge/Testing-Bats-orange?style=flat-square)
![ShellCheck](https://img.shields.io/badge/ShellCheck-Compliant-brightgreen?style=flat-square)

> **语言**: [English](../README.md) | [繁體中文](README.zh-TW.md) | 简体中文 | [日本語](README.ja.md)

> **TL;DR** — 单文件 Bash 脚本，通过 SSH 连接到远程主机，按时间范围查找 log 文件，再用 rsync/scp/sftp 传回本机。100% 测试覆盖率（Bats + Kcov）。
>
> ```bash
> ./pack_log.sh -n 1 -s 260115-0000 -e 260115-2359   # 按主机编号
> ./pack_log.sh -u myuser@10.90.68.188 -s ... -e ...          # 直接指定 user@host
> ./pack_log.sh -l -s ... -e ...                               # 本机模式
> ```

专为机器人车队部署设计的 log 收集工具。自动处理 SSH 连接建立、支持动态 token 解析的时间范围 log 搜索，以及文件传输回本机。

## 功能特点

- **多主机支持**：预设主机列表交互式选择，或直接输入 `user@host`。
- **智能 Log 搜索**：Token 系统支持动态路径解析 — 环境变量（`<env:VAR>`）、Shell 指令（`<cmd:command>`）、日期格式（`<date:%Y%m%d>`）、扩展名筛选（`<suffix:.ext>`）。
- **时间范围筛选**：在指定时间窗口内搜索 log 文件，自动扩展边界确保不遗漏。
- **自动 SSH 密钥管理**：自动创建 SSH 密钥、复制到远程主机、处理 host key 更新。
- **灵活传输方式**：支持 rsync、scp、sftp，自动检测可用工具并依序尝试。
- **本机模式**：不走 SSH，直接在本机收集 log。
- **i18n 多语言支持**：英文、繁体中文、简体中文、日文，通过 `--lang` 或 `$LANG` 切换。
- **Log 文件输出**：所有操作记录写入 `pack_log.log`。
- **模拟执行模式**：预览会收集哪些文件，不做任何复制或传输（`--dry-run`）。
- **传输重试与保留**：文件传输（rsync/scp/sftp）失败时自动重试，最多 3 次，每次间隔 5 秒，能处理 broken pipe 或网络中断等暂时性错误。若全部重试失败，远程临时文件夹会保留以供手动取回。
- **100% 测试覆盖率**：268 个测试，涵盖单元测试、本机集成测试、远程集成测试。

## 快速开始

### 基本使用

```bash
# 交互式选择主机
./pack_log.sh -s 260115-0000 -e 260115-2359

# 按主机编号（HOSTS 数组）
./pack_log.sh -n 1 -s 260115-0000 -e 260115-2359

# 直接指定 user@host
./pack_log.sh -u myuser@10.90.68.188 -s 260115-0000 -e 260115-2359

# 本机模式（不走 SSH）
./pack_log.sh -l -s 260115-0000 -e 260115-2359

# 自定义输出文件夹 + 详细输出
./pack_log.sh -n 1 -s 260115-0000 -e 260115-2359 -o /tmp/my_logs -v

# 使用 token 自定义输出文件夹名称
./pack_log.sh -n 7 -s 260309-0000 -e 260309-2359 -o 'corenavi_<date:%m%d>_#<num>'

# 模拟执行 — 查看会收集哪些文件，不做实际操作
./pack_log.sh -n 1 -s 260115-0000 -e 260115-2359 --dry-run
```

### 命令行选项

| 选项 | 说明 |
|------|------|
| `-n, --number` | 主机编号（对应 `HOSTS` 数组） |
| `-u, --userhost <user@host>` | 直接指定 SSH 目标 |
| `-l, --local` | 本机模式（不走 SSH） |
| `-s, --start <YYmmdd-HHMM>` | 起始时间 |
| `-e, --end <YYmmdd-HHMM>` | 结束时间 |
| `-o, --output <path>` | 输出文件夹路径（支持 `<num>`, `<name>`, `<date:fmt>` token） |
| `-v, --verbose` | 启用详细输出 |
| `--very-verbose` | 启用 debug 输出 |
| `--extra-verbose` | 启用追踪输出（`set -x`） |
| `--dry-run` | 模拟执行：搜索文件但不复制或传输 |
| `--lang <code>` | 语言：`en`、`zh-TW`、`zh-CN`、`ja` |
| `-h, --help` | 显示说明 |
| `--version` | 显示版本 |

## 架构

### 执行流程

```mermaid
graph LR
    A["pack_log.sh\nmain()"]:::entry

    A --> B["option_parser\ngetopt 解析命令行"]:::step
    B --> C["host_handler\n解析目标主机"]:::step
    C --> D["time_handler\n验证时间范围"]:::step
    D --> E{"HOST == local?"}:::decision

    E -->|否| F["ssh_handler\nSSH 密钥 + 连接"]:::step
    F --> G["get_tools_checker\nrsync / scp / sftp"]:::step
    G --> H["folder_creator"]:::step

    E -->|是| H

    H --> I["get_log\n搜索 + 复制文件"]:::step
    I --> J{"HOST == local?"}:::decision

    J -->|否| K["file_sender\n传输回本机"]:::step
    K --> L["完成"]:::output
    J -->|是| L

    classDef entry fill:#1a5276,color:#fff,stroke:#2980b9
    classDef step fill:#8B6914,color:#fff,stroke:#c8960c
    classDef decision fill:#6c3483,color:#fff,stroke:#8e44ad
    classDef output fill:#1e8449,color:#fff,stroke:#27ae60
```

### LOG_PATHS Token 系统

Log 路径支持在运行时对远程主机动态解析的 token：

| Token | 说明 | 示例 |
|-------|------|------|
| `<env:VAR>` | 远程环境变量 | `<env:HOME>/logs` |
| `<cmd:command>` | 远程 shell 指令输出 | `<cmd:hostname>` |
| `<date:format>` | 时间范围筛选用的日期格式 | `<date:%Y%m%d-%H%M%S>` |
| `<suffix:ext>` | 扩展名筛选 | `<suffix:.pcd>` |

**处理链**：`string_handler` → `special_string_parser` → `get_remote_value`

**LOG_PATHS 示例**：
```bash
'<env:HOME>/ros-docker/AMR/myuser/log_core::corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*'
```

### 指令执行模型

所有远程指令都通过 `execute_cmd()` 执行，将指令字符串以 pipe 方式送入 `bash -ls`（本机或 SSH），借此避免 shell 转义问题。`execute_cmd_from_array()` 则处理以 null 分隔的数组 pipe，用于文件操作。

## 配置

编辑 `pack_log.sh` 顶部的 `HOSTS` 和 `LOG_PATHS` 数组：

```bash
# 目标主机: "显示名称::user@host"
declare -a HOSTS=(
  "server01::myuser@10.90.68.188"
  "server02::myuser@10.90.68.191"
)

# Log 路径: "<路径>::<文件样式>"
declare -a LOG_PATHS=(
  '<env:HOME>/logs::app_<date:%Y%m%d%H%M%S>*<suffix:.log>'
  '<env:HOME>/config::node_config.yaml'
)
```

## 项目目录结构

```text
.
├── pack_log.sh                          # 主脚本（约 1980 行）
├── ci.sh                                # CI 入口（unit / integration / all）
├── docker-compose.yaml                  # Docker 服务（ci + sshd + integration）
├── .codecov.yaml                        # Codecov 配置
├── .gitignore
│
├── .github/workflows/
│   ├── main.yaml                        # CI 入口 workflow
│   └── test-worker.yaml                 # 测试 jobs（unit + integration）
│
├── test/
│   ├── test_helper.bash                 # 共用 bats 测试 helper
│   ├── test_log_functions.bats          # 日志函数测试 (20)
│   ├── test_support_functions.bats      # 辅助函数测试 (37)
│   ├── test_option_parser.bats          # 选项解析测试 (44)
│   ├── test_host_handler.bats           # 主机选择测试 (22)
│   ├── test_string_handler.bats         # 字符串/Token 处理测试 (27)
│   ├── test_file_finder.bats            # 文件搜索测试 (20)
│   ├── test_file_ops.bats              # 文件操作测试 (31)
│   ├── test_ssh_handler.bats            # SSH 处理测试 (13)
│   ├── test_main.bats                   # Main 流程测试 (17)
│   ├── test_integration_local.bats      # 本机集成测试 (13)
│   ├── Dockerfile.sshd                  # 远程测试用 SSH 服务器
│   ├── setup_remote_logs.sh             # 远程测试数据创建脚本
│   ├── lib/bats-mock                    # Bats mock 函数库（symlink）
│   └── integration/
│       ├── test_helper.bash             # 远程测试 helper
│       └── test_remote.bats             # 远程集成测试 (24)
│
├── doc/
│   ├── README.zh-TW.md                  # 繁体中文 README
│   ├── README.zh-CN.md                  # 简体中文 README
│   └── README.ja.md                     # 日文 README
│
└── bash_test_helper/                    # 参考架构子模块
```

## 测试

315 个测试（272 单元 + 16 本机集成 + 27 远程集成），**100% 代码覆盖率**。详见 **[TEST.zh-CN.md](../TEST.zh-CN.md)**。

```bash
./ci.sh              # 全部测试（需要 Docker）
./ci.sh unit         # 单元 + ShellCheck + 覆盖率
./ci.sh integration  # 远程集成测试
```

## 重要惯例

- 脚本使用 `set -euo pipefail`，所有错误均为致命错误
- 函数使用 REPLY 惯例作为输出（`REPLY`, `REPLY_TYPE`, `REPLY_STR` 等）
- SSH 密钥路径固定为 `~/.ssh/get_log`
- CI 中强制执行 ShellCheck 合规检查（`-S error` 等级）
- 使用 `BASH_SOURCE` 守卫模式确保可测试性：
  ```bash
  if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
  fi
  ```
