# Changelog

## v1.7.0 (2026-04-10)

### Performance
- **Batched `find` across date-expanded paths**: when a `LOG_PATHS` entry contains a path-level `<date:>` token (e.g. `AvoidStop_<date:%Y-%m-%d>`), `file_finder` now collapses N per-day SSH `find` calls into a single one with multiple starting points. Files are grouped back to their source path via longest-prefix match before dispatch to `file_copier`, preserving the per-day directory structure under `SAVE_FOLDER`.
- **Token prefetch**: new `prefetch_token_cache` runs once after SSH is up, batch-resolving every unique `<env:>` / `<cmd:>` token in `LOG_PATHS` in a single round-trip and seeding `_TOKEN_CACHE`. Subsequent `get_remote_value` calls hit the cache instead of paying RTT cost per unique token. Best-effort: failures fall through to lazy resolution.
- **`get_log` resolution dedup**: `string_handler` and `_needs_sudo` now run exactly once per `LOG_PATHS` entry. Previously `string_handler` was called twice (sudo pre-scan + main loop) and `_needs_sudo` once per date-expanded path.

### UX
- **`Output` summary section**: replaced the per-rpath `Resolved:` log spam with one entry-level line, and added a dedicated `=== Output ===` section at the end showing the full output folder + archive paths (no longer split across `path` / `folder` / `archive` lines), so you can copy-paste them straight into a `cp`.
- **Archive mechanics demoted to debug**: the inner `Creating archive: ...` and `Archive created: ... (size)` lines are now `log_debug`, visible only with `-v`. The `Step 6/6` header stays as a progress milestone.
- **Apparent file size**: archive size now uses `du -h --apparent-size` (real bytes) instead of filesystem block usage. A 200-byte tar.gz no longer reports as `4.0K`.
- **Removed `MSG_PROCESSING`**: dropped the redundant `Processing: <raw>` line that printed before the `Resolved:` line; the resolved view already conveys everything.

### Tests
- New tests for `prefetch_token_cache` (4), `file_finder` array-mode batching (1), `get_log` per-entry batching (3), `archive_save_folder` apparent-size reporting (1), and `main` archive log levels (2).
- 380 unit tests, all green; ShellCheck `-x -S style` clean.

## v1.6.3 (2026-04-09)

### Features
- **Auto archive**: After log collection completes, the script now automatically creates a `.tar.gz` archive alongside the output folder for easy transport. The original folder is preserved. Applies to both local and remote modes; `--dry-run` skips archiving.
- **Interactive failure recovery for archiving**: If `tar` fails (e.g., disk full), the user is prompted with `[R]etry / [K]eep folder only / [A]bort`, mirroring the file_sender failure flow. Any partial/corrupted archive is removed before prompting to avoid misleading output.
- **New output format**: replaced the single `Output folder: ...` line with three lines — `Output path:`, `Output folder:`, and `Output archive:`.
- Pipeline now has 6 steps (was 5); all `MSG_STEP*` labels updated to `N/6`.

### Refactor
- **`have_sudo_access` portability**: replaced hardcoded `/usr/bin/sudo` with `command -v sudo`, working on Alpine / NixOS / macOS Homebrew layouts where sudo is at a different path. As a side benefit, the missing-sudo and sudo-fails branches are now reachable via PATH hijack tests instead of requiring filesystem modification.

### Tests
- New `archive_save_folder` test group (5 tests).
- New PATH hijack tests for `have_sudo_access`.
- 396 tests (341 unit + 23 local integration + 32 remote integration).
- Coverage: **94.79%** (1273/1343).

## v1.6.2 (2026-04-08)

### Tests / Coverage
- **Honest coverage denominator**: removed `KCOV_EXCL` wraps around HOSTS/LOG_PATHS/SSH_OPTS arrays, i18n `load_lang` translation bodies, terminal color detection, and the file_sender retry loop. These blocks were previously hidden from the coverage report, making 100% claims misleading.
- **Mock-based tests**: added in-process tests (not subprocess-wrapped) so kcov can track coverage: `have_sudo_access` with SUDO_ASKPASS and real sudo check, `folder_creator` hostname/date command failures, `file_copier` array-pipe failure, `get_log_dry_run` LOG_PATHS count validation, `get_log` sudo pre-scan failure branch, `file_cleaner` rm failure, `save_script_data` LOG_PATHS count validation, `option_parser` zh-CN LANG auto-detect.
- Coverage: **94.49%** (1166/1234) on the honest denominator (was artificially 93.19% with ~353 lines excluded).
- 380 tests (325 unit + 23 local integration + 32 remote integration).

### Notes on remaining ~68 uncovered lines
- Multi-line bash array literal elements (HOSTS/LOG_PATHS/SSH_OPTS/option_parser opt arrays) — kcov cannot instrument individual element lines inside `declare -a foo=(...)` blocks.
- `[[ -t 2 ]]` terminal color branch — tests run without a real tty (else branch is covered).
- `have_sudo_access` EUID=0 and sudo-missing branches — skipped locally, covered in CI Docker with NOPASSWD sudo.
- Multi-line command substitutions in `log_error` — kcov blind to `$(...)` inner lines.
- Interactive `read -r </dev/tty` single line — kept as `KCOV_EXCL_LINE` (genuinely untestable without a tty).

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
