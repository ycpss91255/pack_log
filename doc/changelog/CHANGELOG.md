# Changelog

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
- 344 tests (282 unit + 21 local integration + 31 remote integration)
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
