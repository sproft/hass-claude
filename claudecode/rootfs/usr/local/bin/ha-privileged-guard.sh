#!/usr/bin/env bash
# shellcheck shell=bash
#
# ha-privileged-guard.sh - Claude Code PreToolUse hook for the Claude Code
# Home Assistant app. It enforces a privileged-action boundary (issue #29):
# some actions can take Home Assistant offline or need physical access to
# recover, so Claude must not run them autonomously.
#
# Why a hook and not just permissions.deny: Claude Code permission rules match
# an MCP tool only by NAME, not by the arguments inside the call. The dangerous
# calls here are ordinary `call_service_tool` invocations whose {domain,service}
# happens to be destructive, so a name-level deny would either block every
# service call or none. This hook reads the actual arguments and decides.
#
# Trust model: the destructive baseline (BUILTIN_DENY / BUILTIN_CONFIRM) is
# hard-coded HERE, in a script that lives on the read-only /usr/local tree
# (AppArmor: /usr/local/** is ixr). The writable policy file can only ADD to the
# baseline, never remove from it, and if that file is missing or corrupt the
# hook fails CLOSED to the baseline rather than open. So config drift, an
# accidental wipe, or an interrupted session cannot silently disable the floor.
# The one lever that disables the guard is an explicit {"enabled":false}, which
# is what the app writes when guard_privileged_actions is turned off. A fully
# adversarial agent with shell write access can still tamper with its own
# settings; this is a strong safety net against mistakes and drift, not a
# sandbox against deliberate self-sabotage.
#
# Contract (Claude Code PreToolUse hook):
#   - Full tool call arrives as JSON on stdin: {tool_name, tool_input, ...}.
#   - To let the normal permission flow proceed, exit 0 with no stdout.
#   - To block or gate, print a decision object on stdout and exit 0:
#       {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#         "permissionDecision":"deny"|"ask","permissionDecisionReason":"..."}}
#     "deny" blocks outright; "ask" forces an interactive human confirmation.
#
# Every vector (MCP call_service_tool, the restart_ha convenience tool, and
# shell commands via curl / the `ha` CLI) is reduced to canonical
# "domain.service" ids, then looked up in the effective lists.

set -u

CONFIG="${HA_GUARD_CONFIG:-/root/.claude/ha-guard.json}"

# Immutable baseline. These are always enforced while the guard is on, even if
# the policy file is gone or malformed. Keep in sync with the config.yaml
# defaults (which are shown to the user); the config lists only ever ADD to this.
# The guard.tamper_* ids are internal (not domain.service, not user-visible in
# config.yaml): they are derived when a tool call writes onto the guard's own
# files, so the header's "mistakes and drift" promise holds under
# bypassPermissions too, where no ordinary permission prompt would catch an
# unintended write. tamper_policy (the guard's policy file) is deny-tier;
# tamper_settings (the settings file carrying the hook + deny floor) is
# confirm-tier so an attended "add a permission rule for me" flow still works.
BUILTIN_DENY="homeassistant.stop supervisor.core_stop supervisor.watchdog_disable hassio.host_reboot hassio.host_shutdown hassio.os_update guard.tamper_policy"
BUILTIN_CONFIRM="homeassistant.restart hassio.supervisor_restart guard.tamper_settings"

# The authority part of a URL pointing at the Supervisor API, used by _api()
# below. Alternatives, in order: any explicit http(s) URL; the `supervisor` and
# `hassio` hostnames written without a scheme; the Supervisor's fixed raw
# address on the add-on network; and a shell variable holding the base URL.
_API_AUTHORITY='(https?://[^[:space:]]*|supervisor|hassio|172\.30\.32\.2|[$]\{?[a-z_][a-z0-9_]*\}?)'

# Invocation of the `ha` CLI, up to but not including its command group. The
# `ha` must sit at a command position -- the start of the command, or right
# after a shell separator (; & | ( ) { } or a backtick) -- so the same verb
# quoted as data inside an echo, a grep pattern, a comment, a heredoc body or a
# doc string is NOT matched (`echo 'run: ha core restart'`, `grep 'ha host
# reboot' file`). That data-vs-command ambiguity is the main false-positive
# source for a text matcher; anchoring on a separator removes most of it. The
# cost is that `ha` reached only through a wrapper (`sudo ha ...`, `sh -c '...'`,
# `xargs ha ...`) is missed, which this app never needs and the MCP path and
# deny floor still cover for the direct forms. Global flags may sit between the
# binary and the command group (`ha --no-progress core stop`), so they are
# skipped here.
_HA_CLI='(^|[|;&(){}`])[[:space:]]*ha([[:space:]]+--[a-z-]+([= ][^[:space:]]+)?)*[[:space:]]+'
# The CLI's command groups carry documented cobra aliases, so `ha ha stop`,
# `ha homeassistant stop`, `ha su restart`, `ha ho reboot` and `ha hassos update`
# are all real spellings of the same operations. Matching only the canonical
# name left every alias unguarded, including past the settings deny floor.
_HA_CORE='(core|homeassistant|home-assistant|ha)'
_HA_HOST='(host|ho)'
_HA_SUPERVISOR='(supervisor|super|su)'
_HA_OS='(os|hassos)'

# jq parses the hook payload. If it is somehow unavailable we cannot read the
# arguments to make a decision, so defer (the settings-level permissions.deny
# floor still covers the worst shell commands). jq is a hard image dependency.
command -v jq >/dev/null 2>&1 || exit 0

# Read the tool call FIRST and derive its action ids before touching the policy
# file: with Write/Edit on the hook matcher this script now runs on every
# ordinary file edit, and the common case (no privileged action implied) must
# exit after one or two jq spawns, not after the four policy-file reads below.
input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ -n "$tool" ] || exit 0

# Emit newline-separated canonical action ids implied by a shell command. The
# patterns only DERIVE the id; whether it is denied/confirmed/allowed is decided
# from the lists, so this stays consistent with the MCP path. Matching arbitrary
# shell text is best-effort by nature: this catches the direct `ha` CLI, curl to
# the Supervisor API, and REST service calls, and normalizes line continuations,
# but deeper obfuscation (variable indirection, base64, an interpreter) is out
# of scope. The MCP path and the settings deny floor are the hard layers.
derive_bash_actions() {
  local cmd out="" seg d s
  # Join `\<newline>` continuations and flatten whitespace so a split command
  # cannot slip past the single-line patterns below. Done with bash parameter
  # expansion (portable, no dependence on sed multiline semantics).
  cmd="$1"
  cmd="${cmd//$'\\\n'/}"   # drop backslash-newline line continuations
  cmd="${cmd//$'\r'/ }"
  cmd="${cmd//$'\t'/ }"
  cmd="${cmd//$'\n'/ }"    # remaining newlines to spaces
  _m() { printf '%s' "$cmd" | grep -Eiq -- "$1"; }

  # Does the line actually make an HTTP request, or invoke the `ha` CLI? The
  # path- and body-shaped patterns below (a REST /services/ segment, a Supervisor
  # /core/stop path, a watchdog:false body) also occur verbatim inside innocent
  # reads: `grep supervisor/os/update file`, `rg services/homeassistant/stop`,
  # `grep watchdog=false home-assistant.log`. Gating those derivations on the
  # presence of an HTTP client (or a URL scheme, or an `ha` invocation) keeps the
  # reads allowed while still catching every real call. The `ha` subcommand
  # patterns are self-anchored on `ha` at a command position and are not gated.
  local has_http=false watchdog_off=false
  { _m '(^|[^[:alnum:]_])(curl|wget|httpie|xh|nc|ncat|socat|aria2c|lynx|links|fetch)([^[:alnum:]_]|$)' \
    || _m 'https?://'; } && has_http=true

  # Match an HTTP request to the Supervisor API for a given path regex,
  # independently of how the host is addressed. The container can reach the
  # Supervisor as http://supervisor/, by its raw IP 172.30.32.2, or through a
  # variable holding the base URL, so anchoring on the literal text
  # "supervisor/core/..." (as this did originally) missed most real requests.
  # Every /core/* lifecycle endpoint is also mirrored by a legacy
  # /homeassistant/* one with identical effect, and the incident in issue #29
  # went through that family, so both spellings are matched. Only fires when the
  # line is an actual HTTP call, so `cat /homeassistant/restart.yaml` (this app's
  # config mount and working directory) is never read as a Supervisor call.
  _api() { [ "$has_http" = true ] && _m "$_API_AUTHORITY$1"'([^[:alnum:]_.-]|$)'; }

  # A bashio helper call. The HA base image ships bashio and every add-on script
  # uses it; these are single tokens with no URL and no `ha ` prefix, e.g.
  # `bashio::core.stop`.
  _bashio() { _m '(^|[^[:alnum:]_])bashio::'"$1"'([^[:alnum:]_]|$)'; }

  # REST service calls of any domain: .../services/<domain>/<service>. Derive
  # the canonical id and let the lists decide (covers homeassistant.stop,
  # hassio.host_reboot, etc. reached via the Core REST API). HTTP context only.
  if [ "$has_http" = true ]; then
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      s="${seg##*/}"; d="${seg%/*}"; d="${d##*/}"
      [ -n "$d" ] && [ -n "$s" ] && out="$out
${d}.${s}"
    done < <(printf '%s' "$cmd" | grep -oiE 'services/[a-z_]+/[a-z_]+' | tr '[:upper:]' '[:lower:]')
  fi

  # Restart Core. Confirmation tier, not a block: a restart is sometimes
  # genuinely needed, it just needs a human to know it is coming. Every verb here
  # matches the `ha` CLI (with its documented cobra aliases and any leading
  # global flags), the /core|/homeassistant REST path, and the bashio helper.
  { _m "$_HA_CLI$_HA_CORE"'[[:space:]]+restart([^[:alnum:]_]|$)' \
    || _api '/(core|homeassistant)/restart' \
    || _bashio 'core\.restart'; } && out="$out
homeassistant.restart"
  # Stop Core -- the second half of the sequence that left the reporter's system
  # needing a power cycle.
  { _m "$_HA_CLI$_HA_CORE"'[[:space:]]+stop([^[:alnum:]_]|$)' \
    || _api '/(core|homeassistant)/stop' \
    || _bashio 'core\.stop'; } && out="$out
supervisor.core_stop"
  # Disable the Supervisor watchdog. The unambiguous CLI flags (--no-watchdog,
  # --watchdog=false) are always honoured. The JSON value form ("watchdog":
  # false) is only ever sent over an HTTP call (the `ha` CLI uses the --watchdog
  # flag, not a JSON body), so it is honoured only when an HTTP client is
  # present -- that keeps `ha addons info | grep 'watchdog: false'` and
  # `grep watchdog=false log` (pure reads) allowed. The quote class allows a
  # backslash because a JSON body written inside a double-quoted shell string
  # arrives as {\"watchdog\": false}, the exact shape the incident used.
  { _m '[-][-]no[_-]?watchdog' \
    || _m '[-][-]watchdog[[:space:]=]+(false|0|off|no)'; } && watchdog_off=true
  if [ "$watchdog_off" = false ] && [ "$has_http" = true ]; then
    _m '[\"'"'"']*watchdog[\"'"'"']*[[:space:]]*[:=][[:space:]]*[\"'"'"']*(false|0|off|no|disabled?)' && watchdog_off=true
  fi
  [ "$watchdog_off" = true ] && out="$out
supervisor.watchdog_disable"
  # Reboot / shut down the host (ha CLI + aliases, Supervisor API, or bashio).
  { _m "$_HA_CLI$_HA_HOST"'[[:space:]]+reboot([^[:alnum:]_]|$)' \
    || _api '/host/reboot' \
    || _bashio 'host\.reboot'; } && out="$out
hassio.host_reboot"
  { _m "$_HA_CLI$_HA_HOST"'[[:space:]]+shutdown([^[:alnum:]_]|$)' \
    || _api '/host/shutdown' \
    || _bashio 'host\.shutdown'; } && out="$out
hassio.host_shutdown"
  # Stop / restart the Supervisor (governed as one id). `reload` is a distinct,
  # harmless refresh and is deliberately NOT matched here.
  { _m "$_HA_CLI$_HA_SUPERVISOR"'[[:space:]]+(restart|stop)([^[:alnum:]_]|$)' \
    || _api '/supervisor/(restart|stop)' \
    || _bashio 'supervisor\.restart'; } && out="$out
hassio.supervisor_restart"
  # OS / host update (ha CLI + hassos alias, or Supervisor API).
  { _m "$_HA_CLI$_HA_OS"'[[:space:]]+update([^[:alnum:]_]|$)' \
    || _api '/os/update'; } && out="$out
hassio.os_update"

  # Shell writes onto the guard's own files: the policy file, or the settings
  # file carrying the hook registration and the permissions.deny floor. Only
  # WRITE shapes are matched (a redirect onto the file, tee, an mv/cp whose
  # DESTINATION is the file, sed -i); reading the same files with cat/grep/jq,
  # or a cp FROM them to a backup, stays allowed. Both the /root/.claude
  # spelling and its symlink target are covered. Best-effort like the rest of
  # this function: a relative path after cd, or an interpreter, is out of
  # scope per the header.
  local gp='(/root/\.claude|/homeassistant/\.claudecode)/ha-guard\.json' \
        sp='(/root/\.claude|/homeassistant/\.claudecode)/settings\.json'
  _writes_to() {
    _m '>>?[[:space:]]*[\"'"'"']*'"$1"'([^[:alnum:]_.]|$)' \
    || _m '(^|[^[:alnum:]_])tee[[:space:]]+(-[a-z]+[[:space:]]+)*[\"'"'"']*'"$1"'([^[:alnum:]_.]|$)' \
    || _m '(^|[^[:alnum:]_])(mv|cp)[[:space:]][^|;&>]*[[:space:]][\"'"'"']*'"$1"'[\"'"'"']*[[:space:]]*([;&|)]|$)' \
    || _m '(^|[^[:alnum:]_])sed[[:space:]]+-[a-z]*i[^|;&]*[[:space:]][\"'"'"']*'"$1"'([^[:alnum:]_.]|$)'
  }
  _writes_to "$gp" && out="$out
guard.tamper_policy"
  _writes_to "$sp" && out="$out
guard.tamper_settings"

  printf '%s\n' "$out"
}

actions=""
case "$tool" in
  *restart_ha)
    actions="homeassistant.restart"
    ;;
  *call_service_tool)
    domain="$(printf '%s' "$input" | jq -r '.tool_input.domain // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    service="$(printf '%s' "$input" | jq -r '.tool_input.service // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    [ -n "$domain" ] && [ -n "$service" ] && actions="${domain}.${service}"
    ;;
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
    [ -n "$cmd" ] && actions="$(derive_bash_actions "$cmd")"
    ;;
  Write|Edit|MultiEdit|NotebookEdit)
    # Guard-file tamper protection. These tools never touch HA services, so the
    # only question is the target path. Both the /root/.claude spelling and its
    # symlink target under /homeassistant/.claudecode must match: readlink
    # closes the gap between them, and if it cannot resolve (target does not
    # exist yet, or busybox quirks) the raw path still matches one spelling.
    fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)"
    [ -n "$fp" ] || exit 0
    rp="$(readlink -f -- "$fp" 2>/dev/null || true)"
    [ -n "$rp" ] || rp="$fp"
    for p in "$fp" "$rp"; do
      case "$p" in
        /root/.claude/ha-guard.json|/homeassistant/.claudecode/ha-guard.json)
          actions="guard.tamper_policy" ;;
        /root/.claude/settings.json|/homeassistant/.claudecode/settings.json)
          [ "$actions" = "guard.tamper_policy" ] || actions="guard.tamper_settings" ;;
      esac
    done
    ;;
  *)
    exit 0
    ;;
esac

# Nothing derived: the overwhelmingly common case. Exit before the policy-file
# reads so ordinary edits and commands pay almost nothing for the guard.
case "$actions" in *[![:space:]]*) ;; *) exit 0 ;; esac

# Resolve the master switch, the unattended flag, and any user-added entries
# from the policy file. Missing/corrupt file -> keep the baseline (fail
# closed). Only an explicit enabled:false disables the guard.
enabled=true
unattended=false
extra_deny='[]'
extra_confirm='[]'
# The env var covers the fail-closed case where the policy file is missing or
# corrupt (it is exported by the boot script when unattended_mode is on); the
# policy-file flag below covers shells that lack the boot environment, such as
# a `docker exec` session. Unattended-if-either fails toward refusing, which
# is the safe direction.
[ "${HA_GUARD_UNATTENDED:-}" = "1" ] && unattended=true
if [ -r "$CONFIG" ]; then
  # Note: `.enabled // true` is WRONG here - jq's // treats a literal false as
  # "absent" and would return true, so the guard could never be switched off.
  # Only an explicit enabled:false disables; anything else stays on.
  e="$(jq -r 'if .enabled == false then "false" else "true" end' "$CONFIG" 2>/dev/null || echo true)"
  [ "$e" = "false" ] && enabled=false
  u="$(jq -r 'if .unattended == true then "true" else "false" end' "$CONFIG" 2>/dev/null || echo false)"
  [ "$u" = "true" ] && unattended=true
  # Keep only the string entries. A wrong-typed value (.deny as a string, or an
  # array holding a number) must not be allowed to reach the union below: it
  # would make that jq expression error out and take the hard-coded baseline
  # down with it. Filtering here means the union can only ever ADD to the
  # baseline, which is the documented contract.
  extra_deny="$(jq -c '[ (.deny // empty | arrays)[] | select(type == "string") ]' "$CONFIG" 2>/dev/null || echo '[]')"
  extra_confirm="$(jq -c '[ (.confirm // empty | arrays)[] | select(type == "string") ]' "$CONFIG" 2>/dev/null || echo '[]')"
fi
[ "$enabled" = "true" ] || exit 0

# Effective, deduped, lower-cased lists = baseline + user additions. The
# fallback is the BASELINE, never an empty list: if anything at all goes wrong
# building the union the guard must still enforce its floor rather than wave
# every action through.
baseline_only() { jq -cn --arg b "$1" '$b | ascii_downcase | split(" ")'; }
deny_all="$(jq -cn --argjson x "$extra_deny" --arg b "$BUILTIN_DENY" \
  '(($b | ascii_downcase | split(" ")) + ($x | map(ascii_downcase))) | unique' 2>/dev/null \
  || baseline_only "$BUILTIN_DENY")"
confirm_all="$(jq -cn --argjson x "$extra_confirm" --arg b "$BUILTIN_CONFIRM" \
  '(($b | ascii_downcase | split(" ")) + ($x | map(ascii_downcase))) | unique' 2>/dev/null \
  || baseline_only "$BUILTIN_CONFIRM")"

# Pick the most restrictive tier across all derived ids: deny > ask > allow.
decision=""
matched=""
in_list() { printf '%s' "$1" | jq -e --arg a "$2" 'index($a)' >/dev/null 2>&1; }
while IFS= read -r a; do
  [ -n "$a" ] || continue
  a="$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')"
  if in_list "$deny_all" "$a"; then
    decision="deny"; matched="$a"; break
  elif in_list "$confirm_all" "$a"; then
    if [ "$decision" != "deny" ]; then decision="ask"; matched="$a"; fi
  fi
done <<EOF
$actions
EOF

[ -n "$decision" ] || exit 0

# Unattended promotion (issue #39 follow-up): an ask with nobody present to
# answer it either hangs an interactive session on a prompt or fails a
# `claude -p` step mid-plan. Refusing fast, with a reason Claude can relay, is
# both safer and more legible. Deny stays deny; the loop above breaks on a
# real deny before an ask can be recorded, so promotion never masks one.
promoted=false
if [ "$decision" = "ask" ] && [ "$unattended" = "true" ]; then
  decision="deny"
  promoted=true
fi

if [ "$decision" = "deny" ]; then
  if [ "$matched" = "guard.tamper_policy" ]; then
    reason="Blocked by the Home Assistant privileged-action guard: that file is the guard's own policy file, managed by this app from its options, and the next app start regenerates it anyway. Editing it directly would change a safety policy without the user's say-so. If the user wants the policy changed, point them at the guard_privileged_actions / disallow_actions / confirm_actions options on the app's Configuration tab. Do NOT try another path or another tool to reach the same file, and do NOT hand the user a shell command, an escape prefix, or any other recipe for bypassing this."
  elif [ "$promoted" = "true" ] && [ "$matched" = "guard.tamper_settings" ]; then
    reason="Blocked by the Home Assistant privileged-action guard: unattended_mode is on, and that file is the Claude Code settings file carrying the guard's hook registration and permission deny floor. With nobody present to review a change to it, the edit is refused. Note what you wanted to change and why, and let the user make the edit in an attended session. Do NOT route around this refusal yourself, and do NOT hand the user a shell command, an escape prefix, or any other recipe for bypassing it."
  elif [ "$promoted" = "true" ]; then
    reason="The Home Assistant privileged-action guard normally lets '${matched}' run after human confirmation, but unattended_mode is on and nobody is present to confirm, so it is refused rather than left waiting on a prompt. Prefer reloading a specific YAML domain (for example automation.reload) if that is enough. If the action is genuinely required, note it plainly and let the user run it in an attended session or from the Home Assistant UI (Settings > System), or turn unattended_mode off first. Do NOT route around this refusal yourself, and do NOT hand the user a shell command, an escape prefix, or any other recipe for bypassing it."
  else
    reason="Blocked by the Home Assistant privileged-action guard: '${matched}' can take Home Assistant offline or require physical access to recover, so it is not allowed autonomously. Prefer reloading a specific YAML domain (for example automation.reload) over stopping or rebooting. If this is genuinely required, say so plainly and let the user do it from the Home Assistant UI (Settings > System), or tell them they can relax the policy themselves via the app's guard_privileged_actions / disallow_actions options. Do NOT route around this block yourself, and do NOT hand the user a shell command, an escape prefix, or any other recipe for bypassing it: naming the action and letting them decide is the whole point of the boundary."
  fi
else
  if [ "$matched" = "guard.tamper_settings" ]; then
    reason="The Home Assistant privileged-action guard asks for human confirmation before this file is edited: it is the Claude Code settings file carrying the guard's hook registration and permission deny floor, so a wrong edit can quietly weaken a safety boundary. Explain exactly what you will change and why, and let the user approve."
  else
    reason="The Home Assistant privileged-action guard requires human confirmation for '${matched}'. Explain to the user what you need and why, and let them approve. A full restart causes a short outage; prefer reloading a specific YAML domain if that is enough. After any state-changing call, re-read the entity to confirm it actually took effect rather than trusting the call's return."
  fi
fi

jq -cn --arg d "$decision" --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
exit 0
