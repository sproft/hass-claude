# Changelog

All notable changes to this project will be documented in this file.

## [1.2.67] - 2026-05-08

### Fixed
- Auto-update of the Claude Code CLI failing/timing out on slow VMs (issue #6, "Still won't update"). The reported log repeated `[WARN] Claude Code update failed/timed out (see /tmp/claude-update.log)` on every restart. Root cause was the hard-coded `timeout 90` wrapper around `npm install -g @anthropic-ai/claude-code@latest`, which is often not enough for `npm` to resolve the registry, fetch the tarball, and install on a memory- or bandwidth-tight Proxmox VM.

### Changed
- New `claude_update_timeout` option (default `300`, range `30..1800`). When `auto_update_claude` is enabled, the boot script now uses this value as the `timeout` for the background `npm install`. The update is already non-blocking (it runs after ttyd is up), so a longer cap is safe.
- `/tmp/claude-update.log` is now appended to instead of overwritten on every boot, and each run is prefixed with a UTC timestamp header. Failure trails survive restarts so users no longer need to catch the file on the right boot.
- On update failure or timeout, the boot script now tails the last 10 lines of `/tmp/claude-update.log` into the addon log (prefixed `  | `), so the actual `npm` error is visible without dropping into the addon shell.

### Added
- GitHub Actions CI (`.github/workflows/ci.yml`):
  - `lint` job: hadolint on the Dockerfile, YAML parse check on `config.yaml` / `build.yaml` / `repository.yaml`, version-vs-CHANGELOG consistency check (enforces the rule from `CLAUDE.md`), and an `options` ↔ `schema` key sync check.
  - `boot-script-shell` job: extracts the embedded `CMD ["/bin/bash","-c", "..."]` boot script via `.github/scripts/extract-boot-script.py`, runs `bash -n` for syntax (blocking) and `shellcheck` (advisory).
  - `build` job: `docker buildx` of the addon image for `linux/amd64` (using GitHub Actions cache), verifies expected tools (`claude`, `jq`, `ttyd`, `node`, `npm`, `hass-mcp`, `tmux`, `docker`, `rg`) are present, and runs the real boot script against a stub `/data/options.json` with `exec ttyd ...` swapped for a marker echo. Asserts the expected `[INFO] MCP configured ...`, `[INFO] Pre-authorized read-only MCP tools`, and `[INFO] auto_update_claude disabled - skipping update` log lines fire. A second smoke run uses `auto_update_claude: true` with a 1-second timeout to exercise the new `[WARN] ... failed/timed out` + tail-on-failure path.

## [1.2.66] - 2026-05-07

### Fixed
- Boot-time `Killed` of `claude mcp` calls on small Proxmox VMs (issue #1, "User Arrival has a Problem"). The reported log showed three back-to-back `claude mcp ... Killed` lines, then `jq: error: Could not open file :` (note the empty filename), then `[WARN] Failed to write pre-authorized tools to settings.json`. ttyd would still come up, but MCP wasn't registered and the read-tool allowlist never landed, so every `claude` session prompted for every read.

### Root cause
Each `claude mcp` invocation spins up a Node process that uses roughly 150 MB resident. With three back-to-back invocations on a memory-tight VM, the OOM killer took them. The old script then chained the `SETTINGS_FILE=...` assignment after `claude mcp add-json` with `&&`, so when the latter was killed the variable never got set, and the downstream `jq` was handed an empty filename.

### Fix
- Replaced the three boot-time `claude mcp ...` invocations with direct `jq` edits to `~/.claude.json` (the same file `claude mcp -s user` writes to). `jq` does the same JSON edit using around 5 MB instead of 150 MB, so OOM is no longer a concern at boot. The `del(.mcpServers.playwright)` clause keeps the old playwright cleanup behaviour for users upgrading from earlier versions.
- Hoisted `SETTINGS_FILE` and `CLAUDE_JSON` variable assignments and the `{}` bootstrap of both files above any conditional logic, so they run unconditionally and the rest of the script never sees an empty filename.
- Wrapped the bootstrap `[ -s "$F" ] || echo '{}' > "$F"` lines in `{ ... ; }` braces so they return a clean exit code into the surrounding `&&` chain regardless of which branch of the `||` runs.

## [1.2.65] - 2026-05-05

### Fixed
- Resolved two Supervisor warnings observed on install:
  - `App has full device access, and selective device access` — removed `uart: true` since it's redundant with `full_access: true`
  - `App config 'arch' uses deprecated values ['armv7', 'armhf', 'i386']` — trimmed `arch:` and `build.yaml` to the still-supported `amd64` and `aarch64` only
- First-launch `jq: error: Could not open file /root/.claude/settings.json: No such file or directory` — startup now creates an empty `settings.json` if missing before merging pre-authorized tools, and falls back to a warning instead of an error if jq still fails. Without this fix, the pre-auth list silently never landed and every read tool prompted for confirmation in the first `claude` session.
- (The `build.yaml is deprecated` notice from Supervisor remains — moving build params into the Dockerfile is a larger change and tracked separately.)

## [1.2.64] - 2026-05-05

### Fixed
- "Killed on startup" on Proxmox HAOS and other small-VM setups (community thread posts 74/75/77):
  - `auto_update_claude` now defaults to `false` so `npm` doesn't run on every restart
  - When auto-update is enabled, it runs in the background with a 90s timeout (no longer blocks ttyd from starting)
  - Added `NODE_OPTIONS=--max-old-space-size=512` to cap npm's heap and avoid OOM kills
  - Reduced tmux `history-limit` from 20,000 → 5,000 lines (saves memory per pane)
  - Healthcheck `start-period` raised from 10s → 120s so Supervisor doesn't kill the addon while it's still booting
- Auto-update reliability (community thread posts 11/26/33): replaced `npm update -g` (often a no-op for global packages) with `npm install -g @anthropic-ai/claude-code@latest`
- OAuth auth-code paste flow (community thread posts 3/4/17/19/56/61/62/65/71): tmux now has bracketed-paste passthrough and `set-clipboard on`, plus expanded README troubleshooting steps

### Changed
- `session_persistence` default flipped from `true` → `false`. tmux's mouse-mode interferes with right-click paste during the OAuth flow, which is the #1 source of new-user friction. Users who want detach/reattach can still opt in.
- Removed Playwright MCP integration and the standalone Playwright Browser add-on. Claude Code's first-party WebFetch / WebSearch tools cover most use cases and the Playwright wiring was a maintenance burden.
- Repository scoped down to a single Claude Code add-on (removed `auto-monocle`).
- Source URL pointed at sproft fork.

## [1.2.63] - 2026-02-23

### Fixed
- Build failure due to `/usr/local/bin/mcp` conflict between hass-mcp (pip) and @playwright/mcp (npm)
- Switched from `npm install -g @playwright/mcp` to npx cache approach (pre-cache during build, `npx --no-install` at runtime)

### Changed
- Playwright Browser add-on: added aarch64 (ARM64) architecture support

## [1.2.62] - 2026-01-26

### Fixed
- MCP token now auto-updates when starting Claude via `c` or `cc` aliases
- Fixes "HTTP error: 500" when SUPERVISOR_TOKEN changes after addon restart

## [1.2.61] - 2026-01-16

### Added
- Full hardware access (`full_access: true`) for Docker socket mounting

## [1.2.60] - 2026-01-16

### Added
- Docker CLI (`docker` command) to use the Docker API

## [1.2.59] - 2026-01-16

### Added
- Docker API access (`docker_api: true`)

## [1.2.58] - 2026-01-16

### Added
- UART/serial port access (`uart: true`)

## [1.2.57] - 2026-01-16

### Added
- `socat` for bidirectional data transfer between channels

## [1.2.56] - 2026-01-16

### Added
- `pyserial` Python library for serial port communication

## [1.2.55] - 2026-01-16

### Fixed
- Removed `unrar` package (not available in Alpine 3.21)
- Use `7z x file.rar` instead for RAR extraction

## [1.2.54] - 2026-01-16

### Added
- Archive tools: `p7zip` for 7-Zip and RAR archives (use `7z` command)
- Modbus tools: `mbpoll` command line Modbus master, `pymodbus` Python library
- Useful for industrial automation and device communication tasks

## [1.2.53] - 2026-01-15

### Added
- Auto-detect Playwright Browser hostname using Supervisor API
- No need to manually configure `playwright_cdp_host` anymore
- Finds any add-on with slug ending in `playwright-browser`

## [1.2.52] - 2026-01-15

### Fixed
- Changed Playwright CDP endpoint from `ws://` to `http://` protocol
- Playwright auto-discovers the WebSocket path via `/json/version`
- Fixes 404 Not Found error when connecting to Chrome CDP

## [1.2.51] - 2026-01-15

### Added
- Configurable `playwright_cdp_host` option for custom Playwright Browser hostname
- Useful when default hostname doesn't resolve (e.g., use `1016f397-playwright-browser`)

## [1.2.50] - 2026-01-15

### Fixed
- Playwright MCP CDP endpoint hostname corrected to `playwright-browser` (was `local-playwright-browser`)
- Fixes "ENOTFOUND local-playwright-browser" connection error

## [1.2.49] - 2026-01-15

### Added
- GitHub CLI (`gh`) for GitHub operations (PRs, issues, repos, etc.)

## [1.2.48] - 2026-01-15

### Changed
- Playwright MCP now connects to external "Playwright Browser" add-on via CDP
- Removed Chromium from this add-on (keeps image small ~100MB vs ~2GB)
- Alpine + Chromium sandbox issues resolved by using separate Ubuntu-based add-on

### Note
- Requires "Playwright Browser" add-on to be installed and running for browser automation

## [1.2.47] - 2026-01-15

### Fixed
- Created `/usr/local/bin/chromium-wrapper` script that always passes `--no-sandbox`
- Playwright MCP config now points to wrapper script
- Should resolve EACCES and sandbox errors when running as root

## [1.2.46] - 2026-01-15

### Fixed
- Playwright MCP now uses config file with system Chromium
- Added `--no-sandbox` and `--disable-dev-shm-usage` flags for container compatibility
- Uses `/usr/bin/chromium-browser` instead of downloaded Chromium

## [1.2.45] - 2026-01-15

### Fixed
- MCP servers now configured at user scope (`-s user`) instead of project scope
- MCPs are now globally available regardless of working directory

## [1.2.44] - 2026-01-14

### Added
- Playwright MCP server for browser automation (opt-in via `enable_playwright_mcp`)
- Headless Chromium browser pre-installed
- Allows Claude to navigate web pages, fill forms, click elements, and take screenshots

## [1.2.43] - 2026-01-14

### Changed
- Upgraded `hassio_role` from `homeassistant` to `manager`
- Enables access to other add-ons' logs via `ha addons logs <slug>`

## [1.2.42] - 2026-01-14

### Added
- `hassio_role: homeassistant` permission for reading core logs
- Fixes 403 error when using `ha core logs`

## [1.2.41] - 2026-01-14

### Added
- Installed Home Assistant CLI (`ha` command) in the container
- `ha core logs`, `ha core restart`, etc. now available

## [1.2.40] - 2026-01-14

### Fixed
- Updated log commands in CLAUDE.md (`ha` CLI not available in add-on containers)
- Now uses `/homeassistant/home-assistant.log` and Supervisor API

## [1.2.39] - 2026-01-14

### Added
- CLAUDE.md now includes Home Assistant logging instructions
  - Log levels explanation (debug, info, warning, error)
  - Commands to read and filter logs
  - How to enable debug logging for integrations

## [1.2.38] - 2026-01-14

### Added
- Pre-authorized read-only hass-mcp tools (no confirmation needed):
  - `get_version`, `get_entity`, `list_entities`, `search_entities_tool`
  - `domain_summary_tool`, `list_automations`, `get_history`, `get_error_log`
- Pre-authorized file read operations:
  - `Read`, `Glob`, `Grep` for `/homeassistant/**`, `/config/**`, `/share/**`, `/media/**`
- Write operations still require confirmation: `entity_action`, `call_service_tool`, `restart_ha`

## [1.2.37] - 2026-01-14

### Added
- Auto-generated `~/.claude/CLAUDE.md` with path mapping instructions
- Claude Code now knows `/config` → `/homeassistant` translation

## [1.2.36] - 2026-01-14

### Fixed
- Reverted `/config` symlink that caused 502 startup errors

## [1.2.35] - 2026-01-14

### Added
- Symlink `/config` → `/homeassistant` for HA path compatibility (reverted in 1.2.36)

## [1.2.34] - 2026-01-14

### Added
- Auto-update Claude Code option (`auto_update_claude`) - checks for updates on startup
- Keeps Claude Code current without requiring add-on version bumps

## [1.2.33] - 2026-01-14

### Added
- Brazilian Portuguese translation (pt-BR)
- Spanish translation (es)

## [1.2.32] - 2026-01-14

### Fixed
- Added .profile to source .bashrc (tmux login shells need this for aliases)

## [1.2.31] - 2026-01-14

### Fixed
- Version bump to force rebuild (1.2.30 may have been cached before alias fix)

## [1.2.30] - 2026-01-14

### Changed
- Reorganized documentation: DOCS.md renamed to README.md
- Simplified root README.md
- Added Quick Start and Requirements sections

### Fixed
- Added .bashrc with aliases (`c`, `cc`, `ha-config`, `ha-logs`) - they were documented but not working

### Removed
- Deleted unused run.sh (Dockerfile CMD has everything inline)

## [1.2.29] - 2026-01-14

### Fixed
- hass-mcp expects `HA_URL` not `HA_HOST`

## [1.2.28] - 2026-01-14

### Changed
- Export HA_TOKEN/HA_HOST as environment variables instead of baking into MCP config
- hass-mcp now reads token from inherited environment (cleaner approach)

## [1.2.27] - 2026-01-14

### Fixed
- hass-mcp expects `HA_TOKEN` and `HA_HOST` (not `HASS_TOKEN`/`HASS_HOST`)

## [1.2.26] - 2026-01-14

### Fixed
- MCP now configured using `claude mcp add-json` command (proper Claude Code API)
- Previous settings.json approach was not recognized by Claude Code

### Documentation
- Added detailed copy/paste instructions for tmux mode (Ctrl+Shift to select, Shift+Insert to paste)

## [1.2.25] - 2026-01-14

### Fixed
- MCP configuration was never created - hass-mcp integration now works
- Added MCP setup to Dockerfile CMD (run.sh was not being executed)
- `/mcp` command now shows Home Assistant MCP server when `enable_mcp: true`

## [1.2.24] - 2026-01-14

### Added
- Improved tmux mouse wheel scrolling support
- Disable alternate screen buffer for better scrollback (`smcup@:rmcup@`)
- Mouse wheel bindings for scrolling in tmux copy mode

### Note
- Mouse scrolling now enabled; use middle-click or Shift+Insert to paste

## [1.2.23] - 2026-01-14

### Added
- Configure tmux with 20,000 line scrollback buffer (`history-limit`)
- Use `Ctrl+b [` then arrow keys/Page Up/Down to scroll in tmux

## [1.2.22] - 2026-01-14

### Added
- Increased terminal scrollback buffer to 20,000 lines (xterm.js)

## [1.2.21] - 2026-01-14

### Reverted
- Removed tmux mouse mode (breaks paste functionality)

### Documentation
- Added section explaining scrolling and session persistence trade-offs

## [1.2.20] - 2026-01-14

### Fixed
- Persist /root/.claude.json file (stores theme/onboarding state)
- Enable tmux mouse support for scroll wheel (`set -g mouse on`)

## [1.2.19] - 2026-01-14

### Fixed
- Store Claude Code data in /homeassistant/.claudecode (truly persistent)
- Survives addon uninstall/reinstall/rebuild
- Symlink ~/.claude and ~/.config/claude-code to HA config directory

## [1.2.18] - 2026-01-14

### Changed
- Sidebar icon changed to mdi:brain

### Fixed
- Persist both ~/.claude and ~/.config/claude-code directories
- Ensures all Claude Code auth and config survives restarts

## [1.2.17] - 2026-01-14

### Fixed
- Persist Claude Code authentication across restarts
- Symlink /root/.claude to /data/claude for persistent storage
- Restored config reading for font size, theme, and session persistence

## [1.2.16] - 2026-01-14

### Fixed
- Restored config reading for font size, theme, and session persistence
- ttyd now applies terminal_font_size, terminal_theme, and session_persistence settings

## [1.2.15] - 2026-01-14

### Fixed
- Refined AppArmor profile with focused permissions for HA config access
- Added dac_read_search capability for directory listing
- Full access to /homeassistant, /share, /media, /config directories
- Read-only access to system files, SSL, backups

## [1.2.14] - 2026-01-14

### Fixed
- Add /etc/** read permissions to AppArmor profile
- Fixes "bash: /etc/profile: Permission denied" error

## [1.2.13] - 2026-01-14

### Fixed
- Add PTY permissions to AppArmor profile (sys_tty_config, /dev/ptmx, /dev/pts/*)
- Fixes "pty_spawn: Permission denied" error when spawning terminal

## [1.2.12] - 2026-01-14

### Fixed
- Use static ttyd binary from GitHub releases instead of Alpine package
- Fixes "failed to load evlib_uv" libwebsockets error

## [1.2.11] - 2026-01-14

### Changed
- Simplified startup: run ttyd directly in CMD without script file
- Minimal configuration for debugging startup issues

## [1.2.10] - 2026-01-14

### Fixed
- Create run.sh inline via heredoc to avoid file permission issues

## [1.2.9] - 2026-01-14

### Fixed
- Add .gitattributes to enforce LF line endings for shell scripts
- Force Docker cache bust for permission fixes

## [1.2.8] - 2026-01-14

### Changed
- Use Docker's tini init system (`init: true`) instead of s6-overlay
- Simplified entrypoint configuration

## [1.2.7] - 2026-01-14

### Fixed
- Use bash instead of bashio in s6-overlay run script
- Add chmod +x /init to fix permission issues

## [1.2.6] - 2026-01-14

### Changed
- Properly configure s6-overlay v3 service structure
- Add service files in /etc/s6-overlay/s6-rc.d/ttyd

## [1.2.5] - 2026-01-14

### Changed
- Attempted switch to pure Alpine base image (reverted due to HA format requirements)

## [1.2.4] - 2026-01-14

### Fixed
- Set `init: false` for s6-overlay v3 compatibility

## [1.2.3] - 2026-01-14

### Fixed
- Force bash entrypoint to bypass s6-overlay init issues

## [1.2.2] - 2026-01-14

### Fixed
- Remove s6-overlay dependency, use plain bash with jq
- Fixes "/init: Permission denied" startup error

## [1.2.1] - 2026-01-14

### Fixed
- Corrected hass-mcp package name (was homeassistant-mcp)
- Upgraded to Python 3.13 base image for hass-mcp compatibility

## [1.2.0] - 2026-01-14

### Changed
- **Security improvement**: Removed API key from add-on config - Claude Code now handles authentication itself
- Simplified Dockerfile - use Alpine's ttyd package instead of architecture-specific downloads
- Removed model selection from config (Claude Code manages this)

### Fixed
- Docker build failure due to BUILD_ARCH variable not being passed correctly

## [1.1.0] - 2026-01-14

### Added
- Model selection option (sonnet, opus, haiku)
- Terminal font size configuration (10-24px)
- Terminal theme selection (dark/light)
- Session persistence using tmux
- s6-overlay service definitions for better process management
- Shell aliases and shortcuts (c, cc, ha-config, ha-logs)
- Welcome banner with configuration info
- Health check for container monitoring

### Changed
- Upgraded to Python 3.12 Alpine base image
- Improved architecture-specific ttyd binary installation
- Enhanced run.sh with better configuration handling
- Better error messages and validation

### Fixed
- Proper ingress base path handling

## [1.0.0] - 2026-01-14

### Added
- Initial release
- Web terminal interface using ttyd
- Claude Code integration via npm package
- Home Assistant MCP server integration for entity/service access
- Read-write access to Home Assistant configuration
- Multi-architecture support (amd64, aarch64, armv7, armhf, i386)
- Ingress support for seamless sidebar integration
