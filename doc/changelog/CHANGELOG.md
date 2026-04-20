# Changelog

## Unreleased

### Features
- **`--no-sync` option**: Skip the file transfer step (rsync/scp/sftp); files remain in the remote temp folder. Useful when network is slow or files should be retrieved manually later. In local mode (`-l`), this option has no effect. Closes #27.

### Bug Fixes
- **`_needs_sudo` HOME prefix collision**: The glob `"${home_dir}"*` matched paths from other users with overlapping prefixes (e.g. `/home/user` matched `/home/username/...`). Switched to `"${home_dir}/"*` for exact directory-boundary comparison. Closes #9.
- **`get_log_dry_run` now uses `_needs_sudo()` for sudo auto-detection**: Previously dry-run only checked the explicit `<sudo>` flag, while `get_log` also auto-detected paths outside HOME. This could cause dry-run to miss files that the real run would find via sudo. Closes #9.
- **`file_finder` find pattern with single quotes**: The `-name` pattern was placed in raw single quotes, so patterns containing `'` would break the generated find command. Added single-quote escaping (`'\''`) while preserving glob characters for find. Closes #9.
- **`time_handler` now rejects equal / reversed times.** Previously `-s 260101-1200 -e 260101-1200` was accepted; the range is empty so the tool silently produced zero files. Switched from lexicographic `>` to `! <`, so anything that isn't strictly `START < END` fails with the existing `MSG_START_BEFORE_END` error. Closes #5.
- **`resolve_path_dates` now picks `step_sec` from the smallest specifier in `<date:fmt>`.** The hard-coded 86400 step skipped 23/24 directories for hourly path tokens like `<date:%Y-%m-%d-%H>`. Day (`%Y-%m-%d`, default), hour (`%H`/`%k`/`%I`/`%l`), minute (`%M`) are supported directly; second-level specifiers (`%S`, `%s`) log a warning and fall back to day step. Closes #5.
- **`file_finder` surfaces batch-parse failures instead of silently dropping files.** When `date -f -` fails during the tolerance path, every candidate was dropped without a log message, so a user seeing zero files had no way to tell it was a `date` error vs. a genuine no-match. Added `MSG_WARN_FILE_FINDER_BATCH_FAILED` via `log_warn`. Closes #5.

### Tests
- `test_option_parser.bats`: 2 new tests covering the strict `START < END` ordering (equal-times and off-by-one rejection) plus an existing test rewritten from "passes" to "exits with error".
- `test_string_handler.bats`: 8 new tests for `resolve_path_dates` fmt-based step — hourly (%H) expansion, minute expansion, second-level warning, month-level dedupe, hourly crossing a day boundary, plus dedicated coverage for the %k / %I / %l hour variants so the step-detection path doesn't regress on non-%H specifiers.
- `test_file_finder.bats`: 1 new test mocking `date -f -` failure and asserting the warning is emitted.
- Coverage expansion filling gaps identified in the same audit that surfaced the bugs above (closes #6):
  - `test_support_functions.bats`: `prefetch_token_cache` reply-count mismatch fallback (previously untested — would silently pair token N with value N-1 on partial remote output).
  - `test_file_ops.bats`: `file_sender` exact `TRANSFER_MAX_RETRIES` invocation count (prior test asserted the failure message, not the loop-boundary count); `archive_save_folder` `[R]etry` loop count via mock that always fails (guards against a silently dropped `continue`).
  - `test_main.bats`: `--dry-run` must not invoke `archive_save_folder`; `--lang ja` and `--lang zh-CN` end-to-end error localization via `time_handler` bad-input path (prior `--lang` tests only exercised `--help`).
  - `test_ssh_handler.bats`: `SSH_KEY` path pointing at an existing directory aborts with `MSG_SSH_KEY_CREATE_FAILED` instead of looping 3x silently.
  - `test_integration_sigint.bats`: SIGTERM mid-spinner leaves no orphan animation process under the parent PID (guards the `trap spinner_stop EXIT` path that the source-level grep test only checks existence of).
- `test_support_functions.bats`: 1 new test for `_needs_sudo` HOME prefix collision (overlapping usernames).
- `test_file_ops.bats`: 1 new test verifying `get_log_dry_run` calls `_needs_sudo()` instead of inlining the flag check.
- `test_file_finder.bats`: 1 new test for filename patterns containing single quotes.
- 464 tests; all green; ShellCheck `-x -S style` clean.

### i18n
- Added `MSG_WARN_DATE_STEP_UNSUPPORTED` and `MSG_WARN_FILE_FINDER_BATCH_FAILED` in all four languages (en / zh-TW / zh-CN / ja).

## v1.8.0 (2026-04-16)

### Features
- **Bandwidth limit (`--bwlimit <rate>`)**: new option to cap transfer throughput, preventing the script from saturating shared network links. Accepts plain KB/s (`500`) or `K` / `M` / `G` suffixes (`500K`, `10M`, `1G`, case-insensitive, trailing `B` optional, IEC 1024-based to match rsync). `0` = unlimited (default). rsync uses `--bwlimit=N` directly; scp/sftp use `-l` in Kbit/s (converted as `N * 8`). Invalid (non-numeric / negative / unsupported suffix) values exit with a clear error. Help text added in all 4 languages. Closes #2.

### Tests
- `test_option_parser.bats`: 27 new tests for `--bwlimit` covering `_parse_bwlimit` helper (plain number, K/KB/M/MB/G/GB suffixes, case-insensitivity, zero, invalid suffix, non-numeric, negative, empty, suffix-only) and `option_parser` integration (unit-suffixed values, invalid unit error).
- `test_file_ops.bats`: 6 new tests for `file_sender` bandwidth-flag wiring (rsync/scp/sftp × limited/unlimited).

## v1.7.2 (2026-04-15)

### Features
- **Liveness spinner**: added `spinner_start` / `spinner_stop` so the user can tell the script is still alive during slow operations (SSH connect, remote find, file copy, archive, folder-size calculation, token prefetch). Non-tty environments print a single status line instead of animating, keeping CI logs clean. Frame cadence is 0.15 s per step.

### Bug Fixes
- **Ctrl-C now actually aborts**: the SIGINT/SIGTERM trap was `file_cleaner` alone, which returned 0 after cleanup — so bash resumed execution at the interrupted line instead of exiting. Changed to `trap 'file_cleaner; exit 130' SIGINT SIGTERM` so Ctrl-C during the remote find / copy phase terminates the script within ~1 s after cleanup.
- **Spinner leak-guard**: added a main-scope `trap spinner_stop EXIT` so an uncaught `set -e` failure mid-animation cannot leave the background frame process running.

### Tests
- New `test_spinner.bats` (10 tests) covering `_spinner_is_tty` override hook, tty / non-tty branches, repeated-start leak protection, and per-language `MSG_SPINNER_*` message coverage.
- New `test_integration_sigint.bats` (4 tests) covering end-to-end SIGTERM trap behavior (exit 130 + SAVE_FOLDER cleanup) and source-level regression guards for both the SIGINT/SIGTERM and EXIT trap lines. SIGINT cannot be tested in non-interactive bats because bash auto-ignores SIGINT in async children and per POSIX the disposition cannot be re-trapped; SIGTERM exercises the identical handler.
- Coverage backfill from kcov audit: `archive_save_folder` failure interactive prompt (`[R]etry` / `[K]eep folder only` / `[A]bort`, 3 tests), `file_sender` >1GB folder-size reporting branch (1 test), `get_log` per-entry `DIR_NOT_FOUND` and `NO_TIME_MATCH` diagnostic warnings (2 tests).
- 439 tests (377 unit + 30 local integration + 32 remote integration); all green; ShellCheck `-x -S style` clean.

### Docs
- `CLAUDE.md` post-change checklist promoted to a mandatory step — doc alignment (README ×4 / CHANGELOG / TEST) and Google Shell Style code review are now required before a change is considered done.

## v1.7.1 (2026-04-10)

### Docs
- Trimmed the header `Usage:` block from 8 examples down to 3 (basic / local / dry-run); the rest are covered by `--help` and were just noise.
- Removed the niche "Renaming the script" paragraph from the header.
- Updated `file_finder` docstring to reflect the v1.7.0 dual-mode first argument (literal path or array name) and documented the previously undocumented `use_mtime` / `use_sudo` arguments.

### Refactor
- Renamed `prefetch_token_cache` locals (`type`/`val`/`pat` → `tok_type`/`tok_val`/`token_pat`) so they no longer shadow the `type` shell builtin.

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
