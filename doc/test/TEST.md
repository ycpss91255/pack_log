# Tests

502 tests (439 unit + 31 local integration + 32 remote integration)

## Unit Tests

| Test File | Tests | Scope |
|-----------|------:|-------|
| `test_log_functions.bats` | 31 | Log output, verbosity, i18n, file descriptor management |
| `test_support_functions.bats` | 56 | `have_sudo_access` (incl. `command -v sudo` PATH hijack), `pkg_install_handler`, `execute_cmd`, `date_format`, `_needs_sudo` (incl. HOME prefix collision), `prefetch_token_cache` (incl. reply-count mismatch fallback) |
| `test_option_parser.bats` | 88 | CLI argument parsing, `SAVE_FOLDER` default, `--dry-run`, `--no-sync`, `--bwlimit` (incl. `_parse_bwlimit` K/M/G[B] suffix handling), `--extra-verbose`, `$LANG` auto-detect, strict `START < END` ordering |
| `test_host_handler.bats` | 22 | Host resolution (`-n`, `-u`, `-l`), interactive mode |
| `test_string_handler.bats` | 44 | Token parsing (`<env:>`, `<cmd:>`, `<date:>`), path splitting, fmt-based step detection (day/hour/minute/sec warn; %H/%k/%I/%l hour variants) |
| `test_file_finder.bats` | 48 | Date filtering, boundary expansion, time tolerance, symlink, auto-mtime, epoch support, batch-parse failure warning, single-quote pattern escaping |
| `test_file_ops.bats` | 82 | `folder_creator`, `file_copier`, `file_sender` (incl. >1GB size branch, `--bwlimit` rsync/scp/sftp, exact `TRANSFER_MAX_RETRIES` invocation count), `get_log` (incl. sudo pre-scan, time-range summary, rsync fallback), `get_log_dry_run` (incl. `_needs_sudo` auto-detection), `file_cleaner`, `archive_save_folder` (incl. [R]etry loop invocation count) |
| `test_ssh_handler.bats` | 14 | SSH key creation, key copy, host key rotation, retry logic, `SSH_KEY` path-is-a-directory guard |
| `test_main.bats` | 42 | Full pipeline (local/remote), dry-run (incl. archive-not-invoked guard), `--no-sync` (skip transfer/archive in remote, no-op in local), transfer failure prompt, archive failure prompt (K/A/retry), `--lang ja` / `--lang zh-CN` end-to-end error localization |
| `test_spinner.bats` | 12 | Liveness spinner (`spinner_start` / `spinner_stop`), tty detection, i18n message coverage |

## Local Integration Tests

`test/test_integration_local.bats` (26 tests):

- Config files, date-filtered files, plain-text extension filtering
- Multiple LOG_PATHS, empty directories, no files in range
- `<env:>` and `<cmd:>` token resolution
- Output folder structure and `/tmp` placement
- Symlink file and symlink directory collection
- Resolved path display
- Cross-date folder expansion
- Epoch and `%Y-%m-%d-%H-%M-%S` date formats
- Full AvoidStop scenario (symlink dir + cross-date + corenavi + rec)
- `get_log` diagnostics: `DIR_NOT_FOUND` and `NO_TIME_MATCH` per-entry warnings

`test/test_integration_sigint.bats` (5 tests):

- SIGTERM during `get_log` triggers trap handler and exits with 130
- SIGTERM cleanup removes `SAVE_FOLDER` via `file_cleaner`
- Source-level guard: `trap 'file_cleaner; exit 130' SIGINT SIGTERM` is installed in `main()`
- Source-level guard: `trap spinner_stop EXIT` is installed for spinner cleanup
- SIGTERM mid-spinner leaves no orphan animation process under the parent PID

## Remote Integration Tests

`test/integration/test_remote.bats` (32 tests):

- SSH connectivity, remote command execution
- File transfer with rsync, scp, sftp (content verification)
- `<cmd:hostname>`, `<env:HOME>` token resolution on remote
- Date format filtering: `%Y%m%d%H%M%S`, `%Y%m%d-%H%M%S`, `%s`, `%Y-%m-%d-%H-%M-%S`
- Plain-text extension filtering, mixed LOG_PATHS
- Directory structure preservation after transfer
- Out-of-range file exclusion (false positive check)
- Symlink file and symlink directory discovery and transfer
- Cross-date folder expansion on remote
- SAVE_FOLDER preserved in `/tmp` after success
- Full scenario (symlink dir + cross-date + corenavi + rec)
