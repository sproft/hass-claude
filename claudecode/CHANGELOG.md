# Changelog

All notable changes to this project will be documented in this file.

## [1.2.84] - 2026-07-26

### Added
- **`unattended_mode` option** (issue #39). Current Claude Code CLI versions refuse `--dangerously-skip-permissions`, and the equivalent `permissions.defaultMode: bypassPermissions`, whenever they detect UID 0 — and this app always runs as root, so any install that set `bypassPermissions` by hand for unattended operation (typically to pair it with the privileged-action guard from #29/#30) started hard-failing on launch once the bundled CLI updated past the version that added that check, with `--dangerously-skip-permissions cannot be used with root/sudo privileges for security reasons`. `IS_SANDBOX=1` is the CLI's own documented opt-out for containerized-root use (`anthropics/claude-code#9184`), but it can't be a plain Dockerfile `ENV`: that's baked at build time, while the setting needs to depend on an app option read from `/data/options.json` at boot. Turning `unattended_mode` on now exports `IS_SANDBOX=1` in the boot script before `ttyd` launches, and sets `permissions.defaultMode` to `bypassPermissions` in the persistent `settings.json`, together, as one deliberate choice. The privileged-action guard is not weakened by this either way: it is a separate `PreToolUse` hook mechanism, so deny-tier actions still block and confirm-tier actions still require your approval regardless of this setting.
- Turning `unattended_mode` back off actively removes a `permissions.defaultMode: bypassPermissions` it finds in `settings.json` on the next boot, rather than leaving it in place. This app's settings file is persistent and shipped changes only ever merge in additively (the same trap the Glob/Grep prune in 1.2.79 and the stray `mcpServers` prune in 1.2.82 both existed for), so simply changing what a future boot *writes* would not undo what an earlier boot already wrote. One consequence worth calling out: this prune also fires on an install that set `permissions.defaultMode: bypassPermissions` by hand before this option existed (the exact scenario reported in #39) — turn `unattended_mode: true` to keep that setting under the new, supported option instead of losing it to the prune.

## [1.2.83] - 2026-07-24

### Changed
- **The privileged-action guard no longer leaves Claude to invent its own workaround when it refuses an action.** Found while exercising the guard on a live install: asked to stop Core, Claude correctly refused and explained why, then helpfully offered the user a ready-to-paste `!`-prefixed shell command to do it anyway. That is not a hole in the boundary (the guard governs what Claude runs, never what a human types, and the human is meant to be the escape hatch), and it satisfied the letter of the old wording, which said to ask the user to perform the action themselves. It is still the wrong thing for an assistant to volunteer: the block exists so a privileged action gets a human decision, and handing over the bypass turns that decision into a formality. It is also the exact sentence a prompt-injection attack would want the assistant to produce. The deny message and the injected `CLAUDE.md` now tell Claude to name the action and point the user at the Home Assistant UI (or at the guard options, if they want the policy itself relaxed), and explicitly not to supply a shell command, an escape prefix, or any other bypass recipe.
- `README.md` documents the three ways to get a blocked action done, in increasing order of bluntness (do it yourself in the HA UI, move the action to `confirm_actions`, or turn the guard off), so the one-off human path is written down rather than rediscovered by the assistant each time. Previously only `guard_privileged_actions: false` was documented, which is a much heavier hammer than a single deliberate action needs.

### CI
- The guard hook step now asserts the deny reason names a human path and does not contain a bypass recipe, so this wording cannot silently regress.
## [1.2.82] - 2026-07-24

### Fixed
- **`working_directory` did nothing.** The option has shipped since early versions and is shown on the Configuration tab in all three languages, but no code ever read it: the boot script hard-coded `cd /homeassistant` before launching the terminal. Setting it to anything else was silently ignored. The boot script now reads the option and starts the terminal there. If the directory does not exist the boot logs a warning and falls back to `/homeassistant`, so a typo cannot leave you without a working terminal.
- **`claude_update_timeout` had no label in the Home Assistant UI.** The option was missing from `translations/en.yaml`, `es.yaml` and `pt-BR.yaml`, so Home Assistant displayed the bare key `claude_update_timeout` with no name or description. Added to all three, including the valid range (30 to 1800) and the fact that it only applies when `auto_update_claude` is on.
- **The `c` and `cc` aliases ran dead code that dirtied `settings.json`.** Both called an `update_mcp_token` function that wrote `.mcpServers.homeassistant.env.HASS_TOKEN` into `/root/.claude/settings.json`. That refreshed nothing: the MCP server is registered in `.claude.json` (as `{"type":"stdio","command":"hass-mcp"}`, with no `env` block), and `hass-mcp` takes its credentials from the `HA_TOKEN` and `HA_URL` variables the boot script exports. So every launch injected an `mcpServers` key into a settings file that has no such setting. The function is removed and the aliases now run `claude` directly. Because that key persists in `/homeassistant/.claudecode/settings.json`, the boot script also deletes it if an older version wrote one, for the same reason the Glob/Grep prune in 1.2.79 was needed: this app's settings file is persistent, so cleaning up shipped mistakes needs an active removal, not just a code change.

### Notes
- All three were found while rewriting the app README and checking every documented option against the code. None of them broke anything outright, which is why they survived: a dead option looks like a working one until you test it, and a stray key in a JSON file is invisible until something validates that file.

## [1.2.80] - 2026-07-24

### Added
- **Privileged-action guard (issue #29, requested by @nickfurnell).** Claude has read/write config access and can call HA services, so it can start a multi-step destructive sequence (the reported incident: disable the Supervisor watchdog, then stop Core) with no guarantee it finishes the sequence if its session context is lost partway. That left Home Assistant stopped with no auto-recovery and needed a host power-cycle. This release adds an enforcement-level boundary instead of relying on convention or in-session memory (which can drift or be overridden). New option `guard_privileged_actions` (default `true`) installs a Claude Code `PreToolUse` hook (`/usr/local/bin/ha-privileged-guard.sh`) that inspects every tool call and applies two tiers: actions in `disallow_actions` are refused outright, and actions in `confirm_actions` require an interactive human approval before they run. Defaults block `homeassistant.stop`, `supervisor.core_stop`, `supervisor.watchdog_disable`, `hassio.host_reboot`, `hassio.host_shutdown`, and `hassio.os_update`, and require confirmation for `homeassistant.restart` and `hassio.supervisor_restart`.
- A `PreToolUse` hook was necessary because Claude Code permission rules match an MCP tool only by name, not by the arguments inside the call. The dangerous calls here are ordinary `call_service_tool` invocations whose `{domain, service}` happens to be destructive, so a name-level `permissions.deny` would block either every service call or none. The hook reduces every path to a canonical `domain.service` id and consults the policy lists: the `call_service_tool` and `restart_ha` MCP tools, and shell commands via the `ha` CLI, a `curl` to the Supervisor API, or a `curl` to the Core REST API (`/api/services/<domain>/<service>`, matched generically so the stop endpoint is covered as well as restart). Shell matching normalizes `\`-newline line continuations first. Read-only queries and normal entity control (`light.turn_on`, and similar) are untouched, and reading logs with `ha core logs` stays allowed; only lifecycle verbs are matched. Matching arbitrary shell text is best-effort by nature (variable indirection, an interpreter, or base64 can evade it); the MCP path, which sees structured arguments, is the reliable layer, and the deny floor below is the fail-closed shell backstop.
- The destructive baseline is hard-coded in the hook itself, which ships on the container's read-only `/usr/local` tree. `disallow_actions` / `confirm_actions` only ever ADD to that baseline, and if the policy file (`/root/.claude/ha-guard.json`) is missing or corrupt the hook falls back to the baseline rather than allowing everything. So config drift, an accidental wipe, or an interrupted session cannot silently lower the floor; only an explicit `guard_privileged_actions: false` disables it. This is a safety net against mistakes and drift, not a sandbox against a deliberately adversarial assistant (settings and the policy file live in a writable directory).
- As a fail-closed backstop, the boot configurator also writes a small fixed set of clearly-destructive shell commands (`ha core stop`, `ha host reboot`/`shutdown`, `ha os update`, plus each verb's documented CLI aliases such as `ha ha stop` and `ha ho reboot`) into `permissions.deny`, which Claude Code enforces even if the hook never runs. This floor is shell-only and, because `permissions.deny` rules are literal command-prefix matches, covers only the `ha` CLI (never a `curl` to the API, nor leading global flags): the MCP `call_service_tool` path and the API forms rely on the hook (`jq` is required for it). Reading verbs like `ha core logs` and `ha core info` are deliberately not in the floor, and neither are `ha core restart` or `ha supervisor restart` (both are confirm-tier and legitimate with a human OK).
- The injected `CLAUDE.md` gains a "Privileged actions and safety" section so every session inherits the policy: never disable the watchdog and stop Core together, treat a full restart as confirmation-required, and never autonomously reboot/shut down the host or update the OS. It also addresses the reporter's second failure mode (a call that returns success yet does nothing, for example an orphaned automation entity that survived a rename) by instructing the assistant to re-read state after any state-changing call rather than trusting the return value. That last part is guidance the assistant is told to follow, not a platform-enforced guarantee like the block/confirm tiers, because a pre-action hook cannot observe a call's after-effects. A human-facing HA notification/banner is intentionally left out of scope and complementary to build.

### Hardened
- **Pre-merge review closed several enforcement gaps in the shell path** (found by driving the real hook against ~140 crafted command shapes). The Supervisor API is now matched independently of how it is addressed: the `http://supervisor/` hostname, the raw IP `172.30.32.2`, and a `$VAR` holding the base URL all resolve, where before only the literal `supervisor/` text did. The deprecated `/homeassistant/*` alias family is matched alongside `/core/*` (the incident's watchdog call went through `/homeassistant/options`, which previously passed), and `/core/restart` is caught, not just `/core/stop`. The `ha` CLI's documented cobra aliases (`ha ha`/`ha homeassistant`/`ha home-assistant` for core, `ha ho` for host, `ha su`/`ha super` for supervisor, `ha hassos` for os) and a leading global flag (`ha --no-progress core stop`) no longer bypass the hook, and `bashio::core.stop`-style helper calls are matched.
- **The hook now fails closed on a malformed policy file, matching its documentation.** A well-formed `ha-guard.json` whose `deny`/`confirm` was the wrong type (a string, or an array with a non-string) previously made the jq union error and collapse the effective list to empty, disabling the guard on every path including MCP. Wrong-typed entries are now filtered out and the fallback is the hard-coded baseline, never an empty list. A zero-byte policy file behaves the same way.
- **Fixed a data-loss bug in the configurator's disable path.** Turning `guard_privileged_actions: false` off ran `.permissions.deny = [ .[] | select(($floor|index(.))|not) ]`, but inside `$floor|index(.)` the `.` rebinds to `$floor`, so it evaluated `index($floor)` = `0` for every element and dropped the user's ENTIRE deny list, not just this app's floor. It now removes the floor with array subtraction (`- $floor`) and only touches keys that already exist.
- **A non-empty but invalid `settings.json` is now repaired, not silently skipped.** Previously every jq edit failed, the guard was left uninstalled for the session, and only a generic WARN was logged. The file is now backed up to `settings.json.corrupt.<ts>` and reset to `{}` so the guard (and the rest of Claude Code) come up, with a loud ERROR naming the backup.
- **Reduced false positives that would push users to turn the guard off.** A denied verb quoted as data (`echo "run: ha core restart"`, `grep 'ha host reboot' file`, a heredoc or doc mentioning a command) is no longer flagged: the `ha` patterns match only at a command position, and the JSON `"watchdog": false` form is honoured only when an HTTP client is present, so `grep watchdog=false log` and reads under `/homeassistant/` (this app's config mount) stay allowed. The trade-off is that `ha` reached only through a wrapper (`sh -c "..."`, `xargs`) is not matched by the shell layer; the MCP path and deny floor still cover the direct forms.

### Changed
- **`hassio.supervisor_restart` sits on the confirm tier, not the block tier.** A Supervisor restart recovers on its own in about 30 seconds, which makes it less disruptive than the `homeassistant.restart` already on that tier (a Core restart takes longer and does not come back at all if the YAML is invalid). Blocking the milder action outright while merely gating the riskier one was inverted, and a non-appealable refusal is the kind of thing that makes people switch the guard off entirely. It was also not among the actions the issue asked to block. `hassio.os_update` stays blocked, as requested there, because a failed OS update can leave the machine needing physical access. The matching `ha supervisor restart` entries are correspondingly out of the fixed `permissions.deny` floor, which only ever carries block-tier verbs.
- The boot script now runs `ha-guard-configure.sh` after the MCP/settings step on every boot. It reads the three new options from `/data/options.json` (falling back to the secure defaults if a key is absent), writes the policy the hook reads to `/root/.claude/ha-guard.json`, and idempotently installs or, when `guard_privileged_actions: false`, removes the hook entry and the deny floor from `settings.json`. Existing user-added hooks and deny rules are preserved (the guard entry is keyed by its command path, and the deny floor is unioned/removed by exact value). The guard logic ships as standalone `rootfs/usr/local/bin/*.sh` scripts pulled in with `COPY`, keeping the embedded boot script small and lintable, the same split adopted for the dotfiles in issue #26. No AppArmor change is needed: `/usr/local/** ixr` already permits executing the scripts and `/root/** rwk` covers the policy file.

### CI
- The boot smoke job gains guard coverage: it asserts `settings.json` ends up with the `PreToolUse` hook wired to the guard script and the `permissions.deny` floor present, and a step drives the real `ha-privileged-guard.sh` inside the built image with crafted `PreToolUse` payloads. It asserts that `homeassistant.stop` / `hassio.host_reboot` (via MCP, via the `ha` CLI, via a `curl` to the REST service path, and via a `\`-newline split command) are denied, `homeassistant.restart` and `restart_ha` ask for confirmation, safe calls (`light.turn_on`, `ha core logs`, a `grep` that merely mentions a service id) pass through, and the baseline is still enforced when the policy file is missing. The `boot-script-shell` job now also shellchecks the two new rootfs scripts (blocking).
- That step is extended with the hardening cases: the `/homeassistant/*` alias, the raw IP `172.30.32.2`, a `$VAR`-addressed call, the `ha` CLI aliases and a leading global flag, `bashio::core.stop`, the wrong-typed-policy fail-closed case, and false-positive guards (an `echo`/`cat`/`grep` that names a command must stay allowed). A new configurator step drives `ha-guard-configure.sh` in the built image and asserts enable/idempotency, that disable preserves the user's own deny rules and hooks while removing only this app's, and that a corrupt `settings.json` is backed up and repaired.

### Notes
- The guard is a safety net, not a replacement for reviewing what your assistant does. It defends the paths this app exposes (the hass-mcp service tools and the shell); it cannot constrain a Supervisor API the container is not given access to. The confirmation tier relies on an interactive terminal to approve the prompt; in a fully non-interactive `claude -p` run an `ask` decision fails safe toward not running. Users who want a hands-on human-in-the-loop pattern (a mobile banner with an abortable countdown) can still build one on top; this release makes the hard floor automatic.
## [1.2.79] - 2026-07-24

### Fixed
- **Claude Code fails to launch in an endless reconnect loop** (issue #33, reported by @nickfurnell). The app pre-authorized its read-only tools with four `Glob(...)` / `Grep(...)` permission rules alongside the equivalent `Read(...)` rules. Current Claude Code CLI versions have consolidated file-read permissions so a `Read(path)` rule covers Read, Glob and Grep, and they now reject the `Glob`/`Grep` spellings: the CLI prints `Permission allow rule ... is not matched by file permission checks`, exits 0 immediately, and ttyd tears the session down, producing a reconnect loop with the app itself healthy. The four rules were redundant from the start, since `Read(/homeassistant/**)` and `Read(/config/**)` were already in the same list, so removing them changes nothing about what Claude may read.
- **Existing installs are repaired on the next start, not just new ones.** Removing the rules from the shipped list alone would have fixed nobody who was already affected: the boot script merges the pre-authorized tools with `.permissions.allow = ($tools + (.permissions.allow // []) | unique)`, which only ever adds, and `settings.json` lives in the persistent `/homeassistant/.claudecode` directory, so the stale rules survive an app update or rebuild. The boot script now actively removes any `Glob(...)` / `Grep(...)` entry from `permissions.allow` and logs which ones it dropped. This runs before the MCP branch and therefore also repairs installs running `enable_mcp: false`, which never reach the pre-authorization step. Rules added by the user are removed too, because the CLI rejects those identically; the log line names every rule removed so the change is not silent.

### Notes
- If the loop has already started, `auto_update_claude: true` plus the Supervisor watchdog turns it into a hard loop (session dies, watchdog restarts the app, the restart pulls the newest CLI, it dies again). Turning `auto_update_claude` off first gives a stable base to update from. After updating to this release the repair happens automatically on the next start and the option can go back on.
- The prune is a no-op on a clean `settings.json`: it rewrites the file and logs only when there is something to remove, so it does not add boot noise or touch a settings file it has already repaired.

## [1.2.78] - 2026-07-19

### Fixed
- **`enable_mcp: false` did not actually disable the MCP integration.** The boot script read the option with `jq -r '.enable_mcp // true'`. jq's `//` operator falls through to the default when the left side is `null` OR `false`, so a literal `false` returned `true`: the guard `if [ "$ENABLE_MCP" = "true" ]` always passed, the Home Assistant MCP server was registered in `.claude.json`, and the read-only tools were pre-authorized, regardless of the setting. The read now uses `jq -r 'if .enable_mcp == false then false else true end'`, so only an explicit `false` disables it (absent or `true` keeps MCP on, matching the default). The other boolean options are unaffected: they default to `false`, and `X // false` yields `false` for both a literal `false` and an absent key, so they were already correct.

### CI
- The `auto_continue` boot smoke (which already runs with `enable_mcp: false`) now asserts the boot logs `[INFO] MCP disabled` and not `[INFO] MCP configured`, guarding against the `// true` regression.

## [1.2.76] - 2026-06-26

### Fixed
- **App build fails with `dockerfile parse error ... unknown instruction: set` on some installs** (issue #26, reported by @davec25 on HA Yellow / aarch64). The Dockerfile wrote `/root/.tmux.conf` and `/root/.bashrc` with shell heredocs (`RUN cat > file << 'EOF' ... EOF`). Heredoc blocks inside a Dockerfile are a BuildKit feature that only activates when the Dockerfile declares a modern frontend via a `# syntax=docker/dockerfile:1.4` (or newer) directive on the first line. This Dockerfile has no such directive, so builders fall back to the Dockerfile parser bundled in the Docker engine, and on older engines that parser does not understand heredocs: it treats the first content line (`set -g history-limit 5000`) as a build instruction and aborts. Because `config.yaml` ships no prebuilt `image:`, every install builds locally from this Dockerfile, so an affected engine cannot install any version at all. It went unreported for many releases because most installs run a newer Docker whose bundled parser handles heredocs. The two dotfiles are now shipped as static files under `claudecode/rootfs/root/` and pulled in with `COPY`, which every Docker version parses regardless of BuildKit. The file contents are byte-for-byte identical to what the heredocs produced (both used a quoted `'EOF'`, so nothing was expanded at build time), so there is no behaviour change. A `.gitattributes` rule pins `claudecode/rootfs/**` to LF so a stray CR from a checkout on Windows cannot break bash sourcing or tmux parsing inside the container.

### Notes
- This is a build-time fix only. Installs already running an affected Docker engine will be able to build and install starting from this release; no change is needed on installs that were already building successfully.

## [1.2.75] - 2026-06-23

### Added
- **`auto_continue` option (default `false`, issue #24, requested by @nickfurnell).** When `session_persistence: true`, the web terminal launches `tmux new-session -A -s claude`, which drops into a bare login shell; after a Home Assistant restart the tmux session is gone, so resuming a conversation means manually typing `c`/`cc`. With `auto_continue: true` the tmux session's startup command becomes `bash -ic cc`, which sources `.bashrc` (so the `update_mcp_token` function and the `cc` alias are defined) and then runs `claude --continue`. `claude --continue` starts a fresh session when there is no prior one, so it is safe to invoke unconditionally. Reusing the existing `cc` alias keeps the MCP-token refresh in one place. The option only takes effect with `session_persistence: true`; without tmux the terminal opens `bash --login` and `auto_continue` is ignored (noted in the option description).

### Changed
- **The boot script now builds the terminal launch command as a bash array (`SHELL_CMD=(...)`) and invokes it as `"${SHELL_CMD[@]}"`** instead of a plain string expanded unquoted. The previous `exec ttyd ... $SHELL_CMD` relied on every token being a single bare word. The `auto_continue` path needs `bash -ic cc` to reach `tmux` as one argument; an unquoted string expansion would word-split it into `bash`, `-ic`, `cc` and hand `tmux` a broken command. The array preserves the sub-command as a single element and is quoted at the launch site, so the grouping survives. The non-persistence (`bash --login`) and plain-persistence (`tmux new-session -A -s claude`) paths are unchanged in behaviour.

### Notes
- With `tmux new-session -A`, reconnecting to an already-running `claude` session reattaches and the startup command is ignored, so a browser refresh while the app is up does not spawn a second Claude. The startup command only runs when the session is first created (container start or after a Home Assistant restart), which is exactly when auto-resume is wanted.
- Because the tmux window's command is `bash -ic cc`, exiting Claude (Ctrl-D or `/exit`) ends that command and closes the window; with a single window the tmux session then ends, the same as exiting the launched shell. Leave `auto_continue: false` (the default) if you prefer to land in a shell and start Claude yourself.

### CI
- The boot smoke test gains a step that drives the real boot script with `session_persistence: true` and both `auto_continue` values, stubs the `exec ttyd` launch with a `printf` over `"${SHELL_CMD[@]}"`, and asserts the constructed argv: with `auto_continue: true` the launch is `tmux new-session -A -s claude` followed by a single `bash -ic cc` argument (guarding against the word-split regression), and with `auto_continue: false` no `bash -ic cc` argument is present. The actual tmux launch and `claude --continue` resume cannot be exercised under `docker run` (no real HA restart, no interactive attach), so resume behaviour still needs a manual check on a real install across a restart.

## [1.2.74] - 2026-06-19

### Fixed
- **`command not found: claude` on a fresh install with Protection mode on** (issue #22). The first-boot seed `cp -a /opt/npm-global/. /data/npm-global/` preserves hard links, and recent Claude Code npm packages ship `bin/claude.exe` as a hard link to the platform binary (`@anthropic-ai/claude-code-linux-x64-musl/claude`). Recreating that link calls `link(2)`, but the AppArmor profile granted `/data/** rwk` and `/data/npm-global/** ixmr`, which union to read/write/lock/exec/mmap with no `l` (link) permission. Under Protection mode the kernel denied `link(2)` (EACCES, which `cp` prints as "Permission denied"), the seed aborted partway, and `claude` never landed on PATH. This is the same Protection-mode-on profile-gap class as #13/#15/#16; it surfaced now because the npm package restructured to ship the native binary as a hard-linked optional dependency. Added `l` to the `/data/npm-global/**` rule. The same permission is required by the `npm install -g ...@latest` auto-update path, which lays out the identical hard link and was being denied too.

### Changed
- **The first-boot seed is now self-healing.** Previously a failed seed left a partial `/data/npm-global` whose top-level `bin/claude` launcher both shadowed the working `/opt/npm-global/bin/claude` on PATH and tripped the old `[ ! -x .../bin/claude ]` guard, so seeding never retried and the install stayed broken. The seed is now gated on a `.seed-complete` marker: a healthy existing tree is adopted as-is (preserving a user's auto-updated copy), otherwise any partial or broken tree is cleared and re-seeded, and on failure the partial copy is removed so the `/opt` fallback still resolves. Installs already broken by #22 recover automatically on the next boot after updating, with no manual `rm -rf /data/npm-global` needed.

### CI
- The boot smoke test now asserts the seed completion marker is written, and a new step simulates a broken partial `/data/npm-global` (an executable but non-working `bin/claude`, no marker) and verifies the boot repairs it and `claude` runs. The AppArmor `l` change itself cannot be exercised in CI, because the smoke test runs under `docker run`, which does not load the Home Assistant AppArmor profile, so it must be verified on a real install with Protection mode on.

## [1.2.73] - 2026-06-19

### Fixed
- **Claude forgets credentials/login after a restart or app configuration change** (issue #20, reported by @kventil). On boot the entrypoint symlinks `/root/.claude.json` to `/homeassistant/.claudecode/.claude.json` so the account record and onboarding state land on the persistent config volume. The MCP-registration step then rewrote that file with `jq ... > /tmp/claude.tmp && mv /tmp/claude.tmp "$CLAUDE_JSON"`. `mv` calls `rename(2)`, which replaces the symlink itself instead of following it, so after the first boot `/root/.claude.json` became a plain file in the container's ephemeral layer. From then on everything Claude wrote to `.claude.json` (the account record, onboarding state) lived only inside the container: a Home Assistant restart re-seeded the file to a bare MCP stub, and an app configuration change recreated the container and wiped it, so Claude came back logged out. The OAuth token in `.credentials.json` was unaffected because it lives inside the already-symlinked `.claude` directory. The fix writes the regenerated JSON to a temp file on the persistent volume and `mv`s it onto the symlink target (`/homeassistant/.claudecode/.claude.json`) instead of onto the link at `/root/.claude.json`. That preserves the symlink and keeps the atomic `rename(2)` of the old code, so the live `.claude.json` is never left half-written if the container is killed mid-boot. (A plain `cat > "$CLAUDE_JSON"` would have fixed the symlink but truncated the file in place, trading the clobber for a crash-time data-loss window.) The temp output is also validated with `jq -e .` before it is promoted, so a truncated or malformed regeneration can never overwrite a good file.

### CI
- The boot smoke test now bind-mounts a host directory at `/homeassistant` and asserts that, after the real boot script runs, the MCP registration is present in the persistent `/homeassistant/.claudecode/.claude.json`. The previous smoke test only mounted `/data` and grepped log lines, so the symlink target lived in the unobserved ephemeral layer and a revert to the symlink-clobbering `mv` would have passed CI green.

### Notes
- Users upgrading from an affected build (1.2.72 or earlier) may have to log in one more time. On the buggy versions the live `.claude.json` was a plain file in the container's ephemeral layer, which Home Assistant discards when it recreates the container for the update, so any account state that never reached the persistent volume cannot be recovered. From the first 1.2.73 boot onward the session persists across restarts and configuration changes.

## [1.2.72] - 2026-05-29

### Fixed
- **`claude` killed with `Permission denied` on a fresh install with Protection mode on** (issues #15, #16). 1.2.71 put `/opt/npm-global/bin` back on `PATH`, so `which claude` resolved again, but the AppArmor profile (`apparmor.txt`) had no rule for `/opt`. With Protection mode enabled, that meant two things: first-boot seeding (`cp -a /opt/npm-global/. /data/npm-global/`) was denied because the source `/opt` was unreadable, so `/data/npm-global` was never populated; and the remaining `/opt/npm-global/bin/claude` could not be executed, so launching it failed with `bash: /opt/npm-global/bin/claude: Permission denied` even though it was on `PATH`. Added `/opt/npm-global/** ixmr` to the profile so the image-baked copy can be read (for seeding into `/data`) and executed (as a fallback). The `/data/npm-global` location was already allowed, so installs that seeded successfully or ran a manual `npm install -g` were unaffected.

### Notes
- This class of bug is invisible to CI: the boot smoke test runs the image with `docker run`, which does not apply Home Assistant's AppArmor profile, so a profile gap cannot be reproduced there. Verify AppArmor changes on a real install with Protection mode on.

## [1.2.71] - 2026-05-28

### Fixed
- **`claude: command not found` in the web terminal after 1.2.70** (issues #15, #16). 1.2.70 moved the npm global prefix off the read-only `/usr/local` tree to `/data/npm-global` and `/opt/npm-global` and added both to `PATH` via the Dockerfile `ENV`. That `ENV PATH` is correct for ordinary processes, but the web terminal opens a login shell (`bash --login`, or tmux when session persistence is on), which sources `/etc/profile`. On the Alpine base image `/etc/profile` resets `PATH` to a fixed default (`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`) that contains neither npm prefix, so the relocated `claude` dropped off `PATH`. Before 1.2.70 the binary lived in `/usr/local/bin`, which is in that default, so it was unaffected. The fix re-adds `/data/npm-global/bin:/opt/npm-global/bin:/root/.local/bin` to `PATH` in `/root/.bashrc`, which login shells source after `/etc/profile` (via `~/.profile`), so the prepend wins.

### CI
- The boot smoke test now asserts that a real login shell (`bash -lc 'command -v claude'`) resolves `claude` on `PATH`. The previous smoke test stubbed out the `exec ttyd` launch and only checked that the seeded binary existed on disk, so it never exercised the login-shell `PATH` reset that caused #15/#16.

## [1.2.70] - 2026-05-26

### Fixed
- Claude Code self-update failing with `EACCES` on `/usr/local/lib/node_modules/...` (issue #13, reported by @nstrelow in HA Community thread post #23). The app runs as root so this was never a Unix ownership problem; the write was blocked by the AppArmor profile, which grants `r`+`ix` on `/usr/local/**` but not `w`. `npm install -g @anthropic-ai/claude-code@latest` (whether invoked by `auto_update_claude` at boot or manually from the app shell) tries to rename the existing package inside `/usr/local/lib/node_modules`, AppArmor denies the write, npm reports `errno -13` and exits 243, and the boot wrapper logs `Claude Code update failed/timed out (exit 243, ...)`. That "timed out" wording was misleading: this was a hard permission denial, distinct from the 300s timeout fixed in 1.2.67.

### Changed
- **Moved the npm global prefix to `/data/npm-global`.** The Dockerfile now installs the image-baked Claude Code into `/opt/npm-global` (via `NPM_CONFIG_PREFIX=/opt/npm-global npm install -g`), and the container sets `NPM_CONFIG_PREFIX=/data/npm-global` plus prepends `/data/npm-global/bin:/opt/npm-global/bin` to `PATH`. The AppArmor profile gains `/data/npm-global/** ixmr,` (the existing `/data/** rwk` rule already covers write/lock; the new rule adds execute and mmap on top via permission union). `/data` is writable and persisted across restarts by the HA Supervisor, so self-updates now land in a location that AppArmor permits and that survives container restarts. `/usr` stays read-only, in line with the 1.2.69 hardening: the app cannot rewrite its own system binaries.
- **First-boot seeding.** The boot script tries `mkdir -p /data/npm-global` and, if `/data/npm-global/bin/claude` is missing, copies `/opt/npm-global/.` into `/data/npm-global/`. Subsequent boots are idempotent and skip the copy. If `/data/npm-global` cannot be created or written (read-only mount, disk full, etc.) the script logs a warning and falls through to the image-bundled `/opt/npm-global/bin/claude` so the app still launches; only `auto_update_claude` is disabled in that degraded mode. PATH ordering means a user-updated Claude Code wins over the image-bundled copy.

### Notes for users on 1.2.69 or older
- After updating to 1.2.70, the first boot will seed `/data/npm-global` from the image. From that point on, `auto_update_claude` and manual `npm install -g @anthropic-ai/claude-code@latest` from the app terminal will both succeed without disabling Protection mode.
- If you previously turned Protection mode off as a workaround and ran a manual `npm install -g` (which wrote into `/usr/local/lib/node_modules`), that copy is in the container's writable layer and will be lost on the next rebuild. After updating to 1.2.70 the persistent `/data/npm-global` copy is authoritative.
- To force a fresh re-seed from the bundled image version (e.g. after a broken self-update), shell into the app and run `rm -rf /data/npm-global` then restart the app.

## [1.2.69] - 2026-05-09

### Security
Scope reductions and supply-chain hardening, ported from [@umrath](https://github.com/umrath)'s sibling fork [umrath/claude-hass-app](https://github.com/umrath/claude-hass-app) with his explicit permission (HA Community thread post #15: "Feel free to incorporate it in your version, @sproft").

- **`full_access: false`** in `claudecode/config.yaml`. Previously `true` (carried from upstream 1.2.61, originally enabled to mount the Docker socket). The Supervisor's full-hardware-access flag is broader than anything the app needs.
- **Dropped `docker_api: true`** from `claudecode/config.yaml`. Docker daemon access from inside the app is effectively root-on-host. Nothing in the default user flow needs it. Users who actually want to run `docker` from inside `claude` can layer it back on locally.
- **Dropped `docker-cli`** from the `apk add` line in `claudecode/Dockerfile`. Coherent with removing `docker_api` — no daemon to talk to.
- **Dropped `capability net_admin`** from `claudecode/apparmor.txt`. The app needs outbound HTTP, not interface/routing/firewall modification. `capability net_raw` is kept (raw sockets for things like ICMP/curl).
- **Pinned `ttyd` binary integrity** in the Dockerfile: SHA256 verified against an explicit list per arch, build fails closed on mismatch. Stops a compromised or replaced GitHub release from silently shipping a different binary.
- **Pinned `mbpoll` source** to the v1.5.4 release tag (`git clone --depth 1 --branch v1.5.4`). Previously cloning unpinned `main`.
- **Sanitized `FONT_SIZE`** read from `/data/options.json` in the boot script (`case $FONT_SIZE in *[!0-9]*|'') FONT_SIZE=14;; esac`). Defence-in-depth: the schema already enforces `int(10,24)`, but if the options file is hand-edited the sanitization keeps a non-numeric value from being interpolated into the `ttyd -t "fontSize=$FONT_SIZE"` invocation.

### Breaking
- Users who relied on running `docker ...` from inside `claude` (anyone who shelled out to the host's Docker daemon) will lose that ability. The app no longer requests `docker_api`, and the `docker` CLI is no longer installed. Add them back in a local override only if you actually need them.

## [1.2.68] - 2026-05-09

### Documentation
- Renamed "add-on" / "addon" to "app" across user-facing prose: top-level README, `claudecode/README.md`, `CLAUDE.md`, the embedded `CLAUDE.md` written by the boot script (Dockerfile lines 157 and 161), the `auto_update_claude` description in `translations/en.yaml` / `es.yaml` / `pt-BR.yaml`, the `# Add-on data` comment in `apparmor.txt`, and the `Build addon image` step name plus a hadolint inline comment in `.github/workflows/ci.yml`. Tracks Home Assistant's own terminology change, flagged by @Sir_Goodenough in the community thread. Fixed identifiers that ride upstream slugs are intentionally left alone: `supervisor_add_addon_repository` (HA Supervisor URL), `addon_config:rw` (HA app map type), `/addon_configs/` (HA mount path), `robsonfelix-hass-addons` (upstream repo name), and historical CHANGELOG entries for releases prior to 1.2.68. Adds a Terminology section to `CLAUDE.md` documenting the split.
- Tightened the wording in the just-shipped 1.2.67 entry to use the new term ("addon log/shell" → "app log/shell", "addon image" → "app image", "in this addon" → "in this app").

## [1.2.67] - 2026-05-08

### Removed
- `pymodbus` and `pyserial` from the `pip install` line. They were inherited from the upstream repository ("for Modbus operations") but nothing in this app actually uses them: Modbus is handled by Home Assistant's own integration, not by code inside the Claude Code container. Drops a few MB off the image and a few seconds off the build. Flagged by @wmaker in the community thread.

### Fixed
- Auto-update of the Claude Code CLI failing/timing out on slow VMs (issue #6, "Still won't update"). The reported log repeated `[WARN] Claude Code update failed/timed out (see /tmp/claude-update.log)` on every restart. Root cause was the hard-coded `timeout 90` wrapper around `npm install -g @anthropic-ai/claude-code@latest`, which is often not enough for `npm` to resolve the registry, fetch the tarball, and install on a memory- or bandwidth-tight Proxmox VM.

### Changed
- New `claude_update_timeout` option (default `300`, range `30..1800`). When `auto_update_claude` is enabled, the boot script now uses this value as the `timeout` for the background `npm install`. The update is already non-blocking (it runs after ttyd is up), so a longer cap is safe.
- `/tmp/claude-update.log` is now appended to instead of overwritten on every boot, and each run is prefixed with a UTC timestamp header. Failure trails survive restarts so users no longer need to catch the file on the right boot.
- On update failure or timeout, the boot script now tails the last 10 lines of `/tmp/claude-update.log` into the app log (prefixed `  | `), so the actual `npm` error is visible without dropping into the app shell.

### Added
- GitHub Actions CI (`.github/workflows/ci.yml`):
  - `lint` job: hadolint on the Dockerfile, YAML parse check on `config.yaml` / `build.yaml` / `repository.yaml`, version-vs-CHANGELOG consistency check (enforces the rule from `CLAUDE.md`), and an `options` ↔ `schema` key sync check.
  - `boot-script-shell` job: extracts the embedded `CMD ["/bin/bash","-c", "..."]` boot script via `.github/scripts/extract-boot-script.py`, runs `bash -n` for syntax (blocking) and `shellcheck` (advisory).
  - `build` job: `docker buildx` of the app image for `linux/amd64` (using GitHub Actions cache), verifies expected tools (`claude`, `jq`, `ttyd`, `node`, `npm`, `hass-mcp`, `tmux`, `docker`, `rg`) are present, and runs the real boot script against a stub `/data/options.json` with `exec ttyd ...` swapped for a marker echo. Asserts the expected `[INFO] MCP configured ...`, `[INFO] Pre-authorized read-only MCP tools`, and `[INFO] auto_update_claude disabled - skipping update` log lines fire. A second smoke run uses `auto_update_claude: true` with a 1-second timeout to exercise the new `[WARN] ... failed/timed out` + tail-on-failure path.

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
