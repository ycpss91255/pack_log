# Tests

398 tests (342 unit + 24 local integration + 32 remote integration)

## Unit Tests

| Test File | Tests | Scope |
|-----------|------:|-------|
| `test_log_functions.bats` | 27 | Log output, verbosity, i18n, file descriptor management |
| `test_support_functions.bats` | 50 | `have_sudo_access` (incl. `command -v sudo` PATH hijack), `pkg_install_handler`, `execute_cmd`, `date_format` |
| `test_option_parser.bats` | 57 | CLI argument parsing, `SAVE_FOLDER` default, `--dry-run`, `--extra-verbose`, `$LANG` auto-detect |
| `test_host_handler.bats` | 22 | Host resolution (`-n`, `-u`, `-l`), interactive mode |
| `test_string_handler.bats` | 37 | Token parsing (`<env:>`, `<cmd:>`, `<date:>`, `<suffix:>`), path splitting |
| `test_file_finder.bats` | 39 | Date filtering, boundary expansion, time tolerance, symlink, mtime, epoch support |
| `test_file_ops.bats` | 67 | `folder_creator`, `file_copier`, `file_sender`, `get_log` (incl. sudo pre-scan, time-range summary, rsync fallback), `file_cleaner`, `archive_save_folder` |
| `test_ssh_handler.bats` | 13 | SSH key creation, key copy, host key rotation, retry logic |
| `test_main.bats` | 30 | Full pipeline (local/remote), dry-run, transfer failure prompt |

## Local Integration Tests

`test/test_integration_local.bats` (24 tests):

- Config files, date-filtered files, suffix filtering
- Multiple LOG_PATHS, empty directories, no files in range
- `<env:>` and `<cmd:>` token resolution
- Output folder structure and `/tmp` placement
- Symlink file and symlink directory collection
- Resolved path display
- Cross-date folder expansion
- Epoch and `%Y-%m-%d-%H-%M-%S` date formats
- Full AvoidStop scenario (symlink dir + cross-date + corenavi + rec)

## Remote Integration Tests

`test/integration/test_remote.bats` (32 tests):

- SSH connectivity, remote command execution
- File transfer with rsync, scp, sftp (content verification)
- `<cmd:hostname>`, `<env:HOME>` token resolution on remote
- Date format filtering: `%Y%m%d%H%M%S`, `%Y%m%d-%H%M%S`, `%s`, `%Y-%m-%d-%H-%M-%S`
- Suffix filtering, mixed LOG_PATHS
- Directory structure preservation after transfer
- Out-of-range file exclusion (false positive check)
- Symlink file and symlink directory discovery and transfer
- Cross-date folder expansion on remote
- SAVE_FOLDER preserved in `/tmp` after success
- Full scenario (symlink dir + cross-date + corenavi + rec)
