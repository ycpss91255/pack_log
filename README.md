# Pack Log [![Test Status](https://github.com/ycpss91255/pack_log/workflows/Main%20CI/CD%20Pipeline/badge.svg)](https://github.com/ycpss91255/pack_log/actions) [![Code Coverage](https://codecov.io/gh/ycpss91255/pack_log/branch/main/graph/badge.svg)](https://codecov.io/gh/ycpss91255/pack_log)

> **Language**: English | [繁體中文](doc/readme/README.zh-TW.md) | [简体中文](doc/readme/README.zh-CN.md) | [日本語](doc/readme/README.ja.md)

![Language](https://img.shields.io/badge/Language-Bash-blue?style=flat-square)
![Testing](https://img.shields.io/badge/Testing-Bats-orange?style=flat-square)
![ShellCheck](https://img.shields.io/badge/ShellCheck-Compliant-brightgreen?style=flat-square)

> **TL;DR** — Single-file Bash script that connects to remote hosts via SSH, finds log files by time range, and transfers them back locally via rsync/scp/sftp.
>
> ```bash
> ./pack_log.sh -n 1 -s 260115-0000 -e 260115-2359   # By host number
> ./pack_log.sh -u myuser@10.90.68.188 -s ... -e ...          # By user@host
> ./pack_log.sh -l -s ... -e ...                               # Local mode
> ```

A single-file log collection tool designed for robotic fleet deployments. It automates SSH connection setup, time-based log file discovery with special token resolution, and file transfer back to the local machine.

## Features

- **Multi-Host Support**: Pre-configured host list with interactive selection, or direct `user@host` input.
- **Smart Log Discovery**: Token system for dynamic path resolution — environment variables (`<env:VAR>`), shell commands (`<cmd:command>`), and date formats (`<date:%Y%m%d>`). File extensions are written inline (e.g., `*.log`).
- **Time-Range Filtering**: Finds log files within a specified time window with automatic boundary expansion. When no exact matches exist, files within a configurable time tolerance (default 30 minutes) are included.
- **Auto SSH Key Management**: Creates SSH keys, copies them to remote hosts, and handles host key rotation automatically. Unknown SSH errors trigger retry instead of fatal exit.
- **Flexible Transfer**: Supports rsync, scp, and sftp with automatic tool detection and fallback. Shows overall transfer progress by default (`--info=progress2`), per-file detail in verbose mode.
- **Large Transfer Warning**: When remote folder exceeds `TRANSFER_SIZE_WARN_MB` (default 300MB), prompts for confirmation before transferring.
- **Transfer Failure Recovery**: Automatically retries failed transfers up to 3 times. When all retries fail, interactively prompts to **[R]etry**, **[K]eep** remote data, or **[C]lean** remote data.
- **Bandwidth Limit**: Throttle transfer speed with `--bwlimit <rate>` to avoid saturating shared network links. Accepts plain KB/s (`500`) or `K` / `M` / `G` suffixes (`500K`, `10M`, `1G`, case-insensitive, trailing `B` optional). rsync uses `--bwlimit`; scp/sftp use `-l` in Kbit/s (auto-converted).
- **Continuous Log Support**: Automatically catches files still being written to — matches by file modification time when filename timestamp is outside the search range.
- **Resolved Path Display**: Shows the actual resolved path (with tokens expanded) alongside the original LOG_PATHS entry during processing.
- **Local Mode**: Run without SSH for local log collection.
- **i18n Support**: English, Traditional Chinese, Simplified Chinese, and Japanese via `--lang` or `$LANG`.
- **Log File Output**: All operations logged to `pack_log.log` in the output folder.
- **Dry-Run Mode**: Preview which files would be collected without any copying or transferring (`--dry-run`).
- **Dynamic Output Naming**: Output folder defaults to `/tmp/<script_name>_<host>_<YYMMDD-HHMMSS>`. The script name is derived from the filename (e.g., renaming `pack_log.sh` to `my_tool.sh` changes the output folder to `my_tool_<host>_...`). Uses HOSTS display name for `-n` mode, hostname for `-l`/`-u` mode. Override with `-o`.
- **Auto Archive**: After collection, automatically creates a `.tar.gz` alongside the output folder for easy transport. Interactive `[R]etry / [K]eep folder only / [A]bort` on failure. Skipped in `--dry-run`.
- **Liveness Spinner**: Animated stderr indicator during slow operations (SSH connect, remote find, copy, archive, size calculation). Non-tty environments fall back to a single status line so CI logs stay clean.
- **Clean Ctrl-C Abort**: Pressing Ctrl-C during any phase removes the temporary output folder and exits with status 130 within ~1 second.
- 439 tests across unit, local integration, and remote integration test suites. CI runs as non-root for realistic permission testing.

## Quick Start

### Basic Usage

```bash
# Select host interactively
./pack_log.sh -s 260115-0000 -e 260115-2359

# By host number (from HOSTS array)
./pack_log.sh -n 1 -s 260115-0000 -e 260115-2359

# Direct user@host
./pack_log.sh -u myuser@10.90.68.188 -s 260115-0000 -e 260115-2359

# Local mode (no SSH)
./pack_log.sh -l -s 260115-0000 -e 260115-2359

# Custom output folder + verbose
./pack_log.sh -n 1 -s 260115-0000 -e 260115-2359 -o /tmp/my_logs -v

# Custom output folder with tokens
./pack_log.sh -n 7 -s 260309-0000 -e 260309-2359 -o 'corenavi_<date:%m%d>_#<num>'

# Dry run — see which files would be collected without copying
./pack_log.sh -n 1 -s 260115-0000 -e 260115-2359 --dry-run

# Throttle transfer on shared networks (plain KB/s or K/M/G[B] suffix)
./pack_log.sh -n 1 -s 260115-0000 -e 260115-2359 --bwlimit 500   # 500 KB/s
./pack_log.sh -n 1 -s 260115-0000 -e 260115-2359 --bwlimit 10M   # 10 MB/s
./pack_log.sh -n 1 -s 260115-0000 -e 260115-2359 --bwlimit 1GB   # 1 GB/s
```

### Command-Line Options

| Option | Description |
|--------|-------------|
| `-n, --number` | Host number (from `HOSTS` array) |
| `-u, --userhost <user@host>` | Direct SSH target |
| `-l, --local` | Local mode (no SSH) |
| `-s, --start <YYmmdd-HHMM>` | Start time |
| `-e, --end <YYmmdd-HHMM>` | End time |
| `-o, --output <path>` | Output folder path (supports `<num>`, `<name>`, `<date:fmt>` tokens) |
| `-v, --verbose` | Enable verbose output |
| `--very-verbose` | Enable debug output |
| `--extra-verbose` | Enable trace output (`set -x`) |
| `--dry-run` | Simulate run: find files without copying or transferring |
| `--no-sync` | Skip transfer; files remain in remote temp folder |
| `--bwlimit <rate>` | Limit transfer bandwidth. Plain number = KB/s; `K`/`M`/`G` suffix (optionally with `B`, case-insensitive) multiplies accordingly. `0` = unlimited |
| `--lang <code>` | Language: `en`, `zh-TW`, `zh-CN`, `ja` |
| `-h, --help` | Show help message |
| `--version` | Show version |

## Architecture

### Execution Pipeline

```mermaid
graph LR
    A["pack_log.sh\nmain()"]:::entry

    A --> B["option_parser\ngetopt CLI parsing"]:::step
    B --> C["host_handler\nresolve target host"]:::step
    C --> D["time_handler\nvalidate time range"]:::step
    D --> E{"HOST == local?"}:::decision

    E -->|No| F["ssh_handler\nSSH key + connection"]:::step
    F --> G["get_tools_checker\nrsync / scp / sftp"]:::step
    G --> H["folder_creator"]:::step

    E -->|Yes| H

    H --> I["get_log\nfind + copy files"]:::step
    I --> J{"HOST == local?"}:::decision

    J -->|No| K["file_sender\ntransfer to local"]:::step
    K --> M["archive_save_folder\ncreate .tar.gz"]:::step
    J -->|Yes| M
    M --> L["Done"]:::output

    classDef entry fill:#1a5276,color:#fff,stroke:#2980b9
    classDef step fill:#8B6914,color:#fff,stroke:#c8960c
    classDef decision fill:#6c3483,color:#fff,stroke:#8e44ad
    classDef output fill:#1e8449,color:#fff,stroke:#27ae60
```

### LOG_PATHS Token System

Log paths support dynamic tokens resolved at runtime on the target host:

| Token | Description | Example |
|-------|-------------|---------|
| `<env:VAR>` | Remote environment variable | `<env:HOME>/logs` |
| `<cmd:command>` | Remote shell command output | `<cmd:hostname>` |
| `<date:format>` | Date format for time filtering | `<date:%Y%m%d-%H%M%S>` |

File extensions are written inline in the pattern (e.g., `*.pcd`); no dedicated token is required.

**Token processing chain**: `string_handler` → `special_string_parser` → `get_remote_value`

**Example LOG_PATHS entry**:
```bash
'<env:HOME>/ros-docker/AMR/myuser/log_core::corenavi_auto.<cmd:hostname>.<env:USER>.log.INFO.<date:%Y%m%d-%H%M%S>*'
```

### Command Execution Model

All remote commands are executed through `execute_cmd()`, which pipes the command string into `bash -ls` (locally or via SSH). This approach avoids shell escaping issues. `execute_cmd_from_array()` handles null-delimited array piping for file operations.

## Configuration

Edit the `HOSTS` and `LOG_PATHS` arrays at the top of `pack_log.sh`:

```bash
# Target hosts: "display_name::user@host"
declare -a HOSTS=(
  "server01::myuser@10.90.68.188"
  "server02::myuser@10.90.68.191"
)

# Log paths: consecutive triplets of (PATH, FILE_PATTERN, FLAGS)
declare -a LOG_PATHS=(
  # PATH                                    FILE_PATTERN                              FLAGS
  '<env:HOME>/config'                       'node_config.yaml'                        ''
  '<env:HOME>/log_core'                     'app.<cmd:hostname>.log.<date:%Y%m%d-%H%M%S>*'  ''
)
```

### LOG_PATHS Format

Each entry is three elements: `"path"  "file_pattern"  "flags"`

**Tokens** (resolved at runtime on the target host):

| Token | Description | Example |
|-------|-------------|---------|
| `<env:VAR>` | Environment variable | `<env:HOME>/logs` |
| `<cmd:command>` | Shell command output | `<cmd:hostname>` |
| `<date:format>` | strftime date format for time filtering | `<date:%Y%m%d-%H%M%S>` |

File extensions are written inline in the pattern (e.g., `*.log`); no dedicated token is required.

**Flags** (third element):

| Flag | Description |
|------|-------------|
| `""` | No special flags (default) |
| `"<sudo>"` | Use `sudo` for find/cp commands — for files requiring root permission (e.g., `/var/log/syslog`) |

**Examples**:

```bash
declare -a LOG_PATHS=(
  # PATH                                         FILE_PATTERN                                                    FLAGS

  # Config file (no date token, always collected)
  "<env:HOME>/core_storage"                       "node_config.yaml"                                              ""

  # Date-filtered files with extension in pattern
  "<env:HOME>/log_data/detection"                 "detect_shelf_<date:%Y%m%d%H%M%S>*.dat"                         ""

  # Epoch-based timestamp
  "<env:HOME>/log_slam"                           "coreslam_2D_<date:%s>*.log"                                    ""

  # Cross-date folder (path contains <date:>, expands all dates in range)
  "<env:HOME>/log/AvoidStop_<date:%Y-%m-%d>"      "<date:%Y-%m-%d-%H.%M.%S>_*_avoid.png"                          ""

  # Continuous log (created once, written until restart — mtime auto-detected)
  "<env:HOME>/log_core"                           "app.<cmd:hostname>.<env:USER>.log.<date:%Y%m%d-%H%M%S>*"      ""

  # System logs requiring sudo (e.g., /var/log/syslog)
  "/var/log"                                      "syslog*"                                                       "<sudo>"
  "/var/log"                                      "kern.log*"                                                     "<sudo>"

  # Using shell variables (defined at script top, expanded at source time)
  "${MY_LOG_PATH}"                                "app_<date:%Y%m%d%H%M%S>*.log"                                 ""
)
```

### HOSTS Format

Each entry is `"display_name::user@host"`:
- `display_name` — a short name for this host (shown in selection menu and output folder)
- `user@host` — SSH login target

#### How to get host information

1. **Find the IP address** — on the remote machine, open a terminal and run:
   ```bash
   hostname -I
   # or
   ip addr show | grep "inet "
   ```
   The IP address looks like `10.90.68.188` or `192.168.1.100`.

2. **Find the username** — on the remote machine, run:
   ```bash
   whoami
   ```
   This gives you the username (e.g., `myuser`).

3. **Test the connection** — on your local machine, run:
   ```bash
   ssh myuser@10.90.68.188
   ```
   If this connects successfully, you have the correct `user@host`.

4. **Add to HOSTS array** — edit `pack_log.sh` and add an entry:
   ```bash
   declare -a HOSTS=(
     "robot-01::myuser@10.90.68.188"
   )
   ```

When running without `-n`, `-u`, or `-l`, the script shows an interactive menu:
```
Select target host:
  1. [robot-01] myuser@10.90.68.188
  2. [robot-02] myuser@10.90.68.191
Enter number, user@host, or 'local':
```

### Tunable Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SSH_TIMEOUT` | 3 | SSH connection timeout (seconds) |
| `TRANSFER_MAX_RETRIES` | 3 | Max transfer retry attempts |
| `TRANSFER_RETRY_DELAY` | 5 | Delay between retries (seconds) |
| `TRANSFER_SIZE_WARN_MB` | 300 | Prompt confirmation when folder exceeds this size (MB) |
| `FILE_TIME_TOLERANCE_MIN` | 30 | Include nearby files within this tolerance when none match the exact range (minutes, 0 to disable) |

## Project Structure

```text
.
├── pack_log.sh                          # Main script
├── ci.sh                                # CI entry point (unit / integration / all)
├── docker-compose.yaml                  # Docker services (ci + sshd + integration)
├── .codecov.yaml                        # Codecov configuration
├── .gitignore
│
├── .github/workflows/
│   ├── main.yaml                        # CI entry workflow
│   └── test-worker.yaml                 # Test jobs (unit + integration)
│
├── test/
│   ├── test_helper.bash                 # Shared bats test helper
│   ├── test_log_functions.bats          # Log function tests (31)
│   ├── test_support_functions.bats      # Support function tests (54)
│   ├── test_option_parser.bats          # Option parser tests (57)
│   ├── test_host_handler.bats           # Host handler tests (22)
│   ├── test_string_handler.bats         # String/token handler tests (36)
│   ├── test_file_finder.bats            # File finder tests (46)
│   ├── test_file_ops.bats              # File operation tests (73)
│   ├── test_ssh_handler.bats            # SSH handler tests (13)
│   ├── test_main.bats                   # Main pipeline tests (35)
│   ├── test_spinner.bats                # Liveness spinner tests (10)
│   ├── test_integration_local.bats      # Local integration tests (26)
│   ├── test_integration_sigint.bats     # Signal trap / Ctrl-C tests (4)
│   ├── Dockerfile.sshd                  # SSH server for remote tests
│   ├── setup_remote_logs.sh             # Remote test data seeder
│   └── integration/
│       ├── test_helper.bash             # Remote test helper
│       └── test_remote.bats             # Remote integration tests (32)
│
├── doc/
│   ├── readme/                          # README translations
│   │   ├── README.zh-TW.md
│   │   ├── README.zh-CN.md
│   │   └── README.ja.md
│   ├── test/
│   │   └── TEST.md                      # Test item list
│   └── changelog/
│       └── CHANGELOG.md                 # Version history
│
```

## Testing

439 tests (377 unit + 30 local integration + 32 remote integration). See **[TEST.md](doc/test/TEST.md)** for full details.

```bash
./ci.sh              # All tests (Docker required)
./ci.sh unit         # Unit + ShellCheck + coverage
./ci.sh integration  # Remote integration tests
```

## Conventions

- Script uses `set -euo pipefail` — all errors are fatal
- Functions use REPLY convention for output (`REPLY`, `REPLY_TYPE`, `REPLY_STR`, etc.)
- SSH key path is fixed at `~/.ssh/get_log`
- ShellCheck compliance enforced in CI (`-S style` level)
- Source guard uses `(return 0 2>/dev/null) || main "$@"` for testability and kcov compatibility
- CI unit tests run as non-root user (`testrunner`) for realistic permission testing
- TDD workflow: write tests first, confirm red, implement, confirm green
