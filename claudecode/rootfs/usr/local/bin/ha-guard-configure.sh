#!/usr/bin/env bash
# shellcheck shell=bash
#
# ha-guard-configure.sh - boot-time configurator for the privileged-action
# guard (issue #29). Called once from the app boot script after the Claude Code
# settings file exists. It:
#   1. Reads the guard options from /data/options.json.
#   2. Writes the policy the runtime hook reads (/root/.claude/ha-guard.json).
#   3. Wires (or, when disabled, unwires) the PreToolUse hook and a small fixed
#      fail-closed permissions.deny floor into the Claude Code settings file.
#
# All settings edits are idempotent (safe to run on every boot) and preserve
# any hooks / deny rules the user added themselves. Kept as a standalone rootfs
# script, not inline in the Dockerfile CMD, so it stays readable and lintable
# (same rationale as the .bashrc / .tmux.conf split in issue #26).

set -u

SETTINGS_FILE="${1:-/root/.claude/settings.json}"
OPTIONS_FILE="${HA_GUARD_OPTIONS:-/data/options.json}"
GUARD_FILE="${HA_GUARD_CONFIG:-/root/.claude/ha-guard.json}"
HOOK_CMD="${HA_GUARD_HOOK:-/usr/local/bin/ha-privileged-guard.sh}"
# Write/Edit/MultiEdit/NotebookEdit are on the matcher for guard-file tamper
# protection only: the hook exits immediately for any file that is not the
# guard's own policy or settings file, so ordinary edits stay un-prompted.
MATCHER="Bash|Write|Edit|MultiEdit|NotebookEdit|mcp__homeassistant__call_service_tool|mcp__homeassistant__restart_ha"

# Defaults must mirror the `options:` block in claudecode/config.yaml. They are
# repeated here so the guard is still safe if options.json is missing a key
# (for example the CI boot smoke fixtures, or a hand-edited file).
DEFAULT_DENY='["homeassistant.stop","supervisor.core_stop","supervisor.watchdog_disable","hassio.host_reboot","hassio.host_shutdown","hassio.os_update"]'
DEFAULT_CONFIRM='["homeassistant.restart","hassio.supervisor_restart"]'
# Fixed, non-configurable settings-level deny floor for the handful of shell
# commands that have no legitimate autonomous use in this app. This is
# fail-closed defense in depth: permissions.deny is enforced by Claude Code
# itself even if the PreToolUse hook is somehow bypassed. Reading logs with
# `ha core logs` / `ha core info` stays allowed - only lifecycle verbs are here.
#
# SCOPE, honestly: permissions.deny rules are literal command-PREFIX matches, so
# this floor can only cover the `ha` CLI, and only the block-tier verbs (never
# `ha core restart`, which is confirm-tier and legitimate with a human OK). It
# does NOT cover a curl to the Supervisor API, nor leading global flags
# (`ha --raw core stop`). Those rely on the hook, which reads structured
# arguments. The floor lists the documented cobra aliases for each verb
# (`ha ha`/`ha homeassistant`/`ha home-assistant` for core, `ha ho` for host,
# `ha su`/`ha super` for supervisor, `ha hassos` for os) so the most obvious
# spellings are covered even without the hook.
DENY_FLOOR='["Bash(ha core stop:*)","Bash(ha ha stop:*)","Bash(ha homeassistant stop:*)","Bash(ha home-assistant stop:*)","Bash(ha host reboot:*)","Bash(ha ho reboot:*)","Bash(ha host shutdown:*)","Bash(ha ho shutdown:*)","Bash(ha os update:*)","Bash(ha hassos update:*)"]'

if ! command -v jq >/dev/null 2>&1; then
  echo '[WARN] jq unavailable; privileged-action guard not configured'
  exit 0
fi

# Resolve options with defaults.
# `.guard_privileged_actions // true` is WRONG: jq's // treats a literal false
# as absent and returns true, so the option could never turn the guard off.
# Only an explicit false disables it.
ENABLED="$(jq -r 'if .guard_privileged_actions == false then "false" else "true" end' "$OPTIONS_FILE" 2>/dev/null || echo true)"
case "$ENABLED" in false) ENABLED=false ;; *) ENABLED=true ;; esac
# unattended_mode is stamped into the policy file so the runtime hook can
# promote confirm-tier asks to denies while nobody is present to answer them.
# Explicit == comparison, same convention as the boot script's option reads.
UNATTENDED="$(jq -r 'if .unattended_mode == true then "true" else "false" end' "$OPTIONS_FILE" 2>/dev/null || echo false)"
case "$UNATTENDED" in true) UNATTENDED=true ;; *) UNATTENDED=false ;; esac
# Lower-case list entries so a mixed-case config entry still matches (the hook
# lower-cases the incoming domain.service before looking it up).
DENY_JSON="$(jq -c --argjson d "$DEFAULT_DENY" '(.disallow_actions // $d) | map(ascii_downcase)' "$OPTIONS_FILE" 2>/dev/null || echo "$DEFAULT_DENY")"
CONFIRM_JSON="$(jq -c --argjson c "$DEFAULT_CONFIRM" '(.confirm_actions // $c) | map(ascii_downcase)' "$OPTIONS_FILE" 2>/dev/null || echo "$DEFAULT_CONFIRM")"

# Write the policy file the runtime hook reads.
if jq -cn --argjson e "$ENABLED" --argjson d "$DENY_JSON" --argjson c "$CONFIRM_JSON" \
     --argjson u "$UNATTENDED" \
     '{enabled:$e,deny:$d,confirm:$c,unattended:$u}' > "$GUARD_FILE.tmp" 2>/dev/null; then
  mv "$GUARD_FILE.tmp" "$GUARD_FILE"
else
  rm -f "$GUARD_FILE.tmp"
  echo '[WARN] Failed to write privileged-action guard policy'
fi

# Make sure the settings file exists and is valid JSON before editing it. A
# non-empty but malformed file would make every jq edit below fail and, on the
# old code, silently leave the guard uninstalled for the whole session while
# printing only a generic WARN. (Claude Code cannot parse it either, so the
# session is already degraded.) Back the file up and start from a clean object
# so the guard -- and the rest of Claude Code -- still come up, and log a loud
# ERROR naming the backup so the user can merge their settings back.
mkdir -p "$(dirname "$SETTINGS_FILE")"
if [ ! -s "$SETTINGS_FILE" ]; then
  echo '{}' > "$SETTINGS_FILE"
elif ! jq -e . "$SETTINGS_FILE" >/dev/null 2>&1; then
  backup="$SETTINGS_FILE.corrupt.$(date +%s 2>/dev/null || echo bak)"
  cp -f "$SETTINGS_FILE" "$backup" 2>/dev/null || true
  echo '{}' > "$SETTINGS_FILE"
  echo "[ERROR] $SETTINGS_FILE was not valid JSON; backed it up to $backup and reset it so the privileged-action guard could be installed. Re-merge any custom settings from the backup."
fi

TMP="$(dirname "$SETTINGS_FILE")/.settings.guard.tmp"

if [ "$ENABLED" = "true" ]; then
  # Install: drop any previous guard hook entry (idempotent across reboots),
  # add ours, and union the deny floor in. User-added hooks/denies are kept.
  if jq --arg hook "$HOOK_CMD" --arg matcher "$MATCHER" --argjson floor "$DENY_FLOOR" '
        .hooks = (.hooks // {})
        | .hooks.PreToolUse = (
            [ (.hooks.PreToolUse // [])[]
              | select( ([ .hooks[]? | .command ] | index($hook)) | not ) ]
            + [ { matcher: $matcher, hooks: [ { type: "command", command: $hook, timeout: 10 } ] } ] )
        | .permissions = (.permissions // {})
        | .permissions.deny = (((.permissions.deny // []) + $floor) | unique)
      ' "$SETTINGS_FILE" > "$TMP" 2>/dev/null && mv "$TMP" "$SETTINGS_FILE"; then
    echo "[INFO] Privileged-action guard active (deny=$(printf '%s' "$DENY_JSON" | jq 'length'), confirm=$(printf '%s' "$CONFIRM_JSON" | jq 'length'))"
  else
    rm -f "$TMP"
    echo '[WARN] Failed to install privileged-action guard into settings.json'
  fi
else
  # Disabled: remove our hook entry and the deny floor; leave everything else.
  # Only touch keys that already exist, so disabling does not scaffold empty
  # .hooks / .permissions objects onto a settings file that had none. The deny
  # floor is removed with array subtraction (A - $floor): the previous
  # `select( ($floor | index(.)) | not )` was a bug -- inside `$floor | index(.)`
  # the `.` rebinds to $floor, so it evaluated `$floor | index($floor)` = 0 for
  # every element, and `0 | not` is false, which dropped the user's ENTIRE deny
  # list (their own unrelated safety rules included), not just the floor.
  if jq --arg hook "$HOOK_CMD" --argjson floor "$DENY_FLOOR" '
        (if (.hooks.PreToolUse | type) == "array" then
            .hooks.PreToolUse = [ .hooks.PreToolUse[]
              | select( ([ .hooks[]? | .command ] | index($hook)) | not ) ]
         else . end)
        | (if (.permissions.deny | type) == "array" then
            .permissions.deny = ( .permissions.deny - $floor )
         else . end)
      ' "$SETTINGS_FILE" > "$TMP" 2>/dev/null && mv "$TMP" "$SETTINGS_FILE"; then
    echo '[INFO] Privileged-action guard disabled (guard_privileged_actions: false)'
  else
    rm -f "$TMP"
    echo '[WARN] Failed to remove privileged-action guard from settings.json'
  fi
fi

exit 0
