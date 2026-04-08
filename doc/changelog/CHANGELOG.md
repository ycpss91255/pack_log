# Changelog

## v1.6.1 (2026-04-08)

### Bug Fixes
- **`$LANG` auto-detect broken**: source-time `LANG_CODE="en"` override defeated locale auto-detection. Users had to pass `--lang` explicitly. Now empty at source time so `$LANG` (local env, not remote) is honored.
- **Missing summary warning**: `MSG_NO_FILES_IN_RANGE` was defined in all locales but never emitted. `get_log()` now warns once at the end when no files were found across the entire time range.

### Tests / Coverage
- Audited all `KCOV_EXCL` markers. Removed exclusions on plain-logic blocks (have_sudo_access body, error log one-liners, ssh_handler failure, tool checker fallback, sudo pre-scan, LANG auto-detect, etc.) and kept exclusions only on site config data, i18n translation bodies, terminal detection, interactive prompts, integration-only file_sender loops, and source guard.
- 366 tests (311 unit + 23 local integration + 32 remote integration).
- New tests: sudo pre-scan branch in `get_log`, LANG env regression without manual reset, get_tools_checker rsync fallback, get_remote_value env+remote printf -v branch, time-range summary warning (positive + negative).

## v1.6.0 (2026-04-01)

### Features
- **LOG_PATHS triplet format**: `(path, pattern, flags)` with `<mtime>` flag for continuous log files
- **Cross-date folder support**: `AvoidStop_<date:%Y-%m-%d>` expands all dates from START to END
- **Symlink support**: `find -L` follows symlink directories, `-type l` matches symlink files
- **Epoch tolerance fix**: `%s` format timestamps handled correctly in tolerance path
- **Interactive transfer failure**: [R]etry / [K]eep / [C]lean prompt when all retries fail
- **Large transfer warning**: Prompt when folder exceeds `TRANSFER_SIZE_WARN_MB` (default 300MB)
- **rsync overall progress**: `--info=progress2` by default, per-file detail in verbose
- **Resolved path display**: Shows actual paths after token expansion
- **Dynamic output naming**: Folder named after script basename + host label + `%y%m%d-%H%M%S`
- **SAVE_FOLDER under /tmp**: Preserved after success for debug
- **Time tolerance**: `FILE_TIME_TOLERANCE_MIN` (default 30 min) for nearby files
- **`--lang` validation**: Warns on invalid language code, falls back to English
- **HOSTS beginner guide**: Step-by-step instructions in README
- **`COREROBOT_*` path variables**: Simplify LOG_PATHS configuration

### Bug Fixes
- `folder_creator`: Strip `<num>`/`<name>` tokens when NUM is empty
- `pkg_install_handler`: Return 1 on apt-get failure (was returning 0)
- `ssh_handler`: Unknown SSH errors use `log_warn` instead of fatal `log_error`
- `file_finder`: Replace date token with `*` in find pattern, collapse `**`
- `have_sudo_access`: Use `if` block for sudo check (set -e safe)
- `ssh-keyscan`/`ssh-keygen -R`: Add `|| true` for set -e safety
- Missing `MSG_OUTPUT_FOLDER` in zh-TW i18n
- Missing `MSG_RESOLVED_PATH` translation for zh-TW/zh-CN/ja
- Array index syntax `${raw_files[i]}` → `${raw_files[${i}]}`
- LOG_PATHS element count validation (warn if not multiple of 3)

### Refactoring
- LOG_PATHS: `::` delimited → consecutive pairs → triplets with flags
- Test framework: `set +euo pipefail` → `set +u +o pipefail` (keeps `-e` for bats failure detection)
- Source guard: `BASH_SOURCE` → `(return 0 2>/dev/null) || main "$@"`
- `run bash -c`: Add `env -u LD_PRELOAD -u BASH_ENV` for kcov compatibility
- CI: Run tests as non-root user (`testrunner`) with sudo + rsync installed
- ShellCheck: Upgraded to `-S style` (strictest level)
- Doc structure: `doc/readme/`, `doc/test/`, `doc/changelog/`

### Tests
- 360 tests (296 unit + 23 local integration + 32 remote integration)
- Fixed 28+ false-positive tests exposed by test framework fix
- Added: symlink dir, cross-date folder, mtime, epoch tolerance, root EUID,
  real-world scenario, stat failure, locale detection, LOG_PATHS validation,
  i18n completeness tests

## v1.5.0 (2026-03-31)

### Features
- **LOG_PATHS triplet format**: `(path, pattern, flags)` with `<mtime>` flag for continuous log files
- **Cross-date folder support**: `AvoidStop_<date:%Y-%m-%d>` expands all dates from START to END
- **Dynamic output naming**: Folder named after script basename + HOSTS display name or hostname
- **Output timestamp**: `%y%m%d-%H%M%S` (2-digit year)
- **SAVE_FOLDER under /tmp**: Preserved after success for debug
- **Interactive transfer failure prompt**: [R]etry / [K]eep / [C]lean
- **Large transfer warning**: Prompt when folder exceeds `TRANSFER_SIZE_WARN_MB` (default 300MB)
- **rsync overall progress**: `--info=progress2` by default, per-file detail in verbose
- **Resolved path display**: Shows actual paths after token expansion
- **Time tolerance**: `FILE_TIME_TOLERANCE_MIN` (default 30 min) for nearby files
- **Symlink support**: `find -L` follows symlink directories, `-type l` matches symlink files

### Bug Fixes
- `folder_creator`: Strip `<num>`/`<name>` tokens when NUM is empty
- `pkg_install_handler`: Return 1 on apt-get failure (was returning 0)
- `ssh_handler`: Unknown SSH errors use `log_warn` instead of fatal `log_error`, allowing retry
- `file_finder`: Replace date token with `*` in find pattern (was removing it)
- `(( e_idx++ ))`: Use pre-increment to avoid exit code 1 at zero
- `have_sudo_access`: Use `if` block for sudo check (set -e safe)

### Refactoring
- LOG_PATHS: `::` delimited → consecutive pairs → triplets with flags
- Test framework: `set +euo pipefail` → `set +u +o pipefail` (keeps `-e` for bats failure detection)
- Source guard: `BASH_SOURCE` → `(return 0 2>/dev/null) || main "$@"`
- `run bash -c`: Add `env -u LD_PRELOAD -u BASH_ENV` for kcov compatibility
- CI: Run tests as non-root user (`testrunner`) with sudo + rsync installed
- Doc structure: `doc/readme/`, `doc/test/`, `doc/changelog/`

### Tests
- 360 tests (296 unit + 23 local integration + 32 remote integration)
- Fixed 28+ false-positive tests exposed by test framework fix
- Added: symlink dir, cross-date folder, mtime, root EUID, real-world scenario tests
- Removed duplicate tests and empty skip placeholders

## v1.4.0 (2026-03-25)

### Features
- `--dry-run` mode: Preview files without copying or transferring
- Output folder tokens: `<num>`, `<name>`, `<date:fmt>` in `-o` path
- i18n embedded translations (en, zh-TW, zh-CN, ja) — removed external `doc/lang/` files

### Refactoring
- Variable reorganization
- Merged CI scripts into single `ci.sh` with subcommands

## v1.3.0

- `--version` flag
- Time validation improvements
- Local env optimization

## v1.2.0

- Test infrastructure (Bats + Kcov)
- Bug fixes and robustness improvements
