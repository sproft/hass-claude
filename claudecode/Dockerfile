ARG BUILD_FROM
FROM ${BUILD_FROM}

# Labels
LABEL org.opencontainers.image.title="Claude Code for Home Assistant"
LABEL org.opencontainers.image.description="Claude Code CLI with web terminal and HA integration"
LABEL org.opencontainers.image.source="https://github.com/sproft/hass-claude"
LABEL org.opencontainers.image.licenses="MIT"

# Environment setup
ENV \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color

# Install system dependencies (ttyd installed separately as static binary)
RUN apk add --no-cache \
    bash \
    curl \
    git \
    github-cli \
    jq \
    nodejs \
    npm \
    openssh-client \
    libstdc++ \
    ncurses \
    vim \
    nano \
    tmux \
    coreutils \
    findutils \
    grep \
    sed \
    gawk \
    ca-certificates \
    openssl \
    ripgrep \
    p7zip \
    socat \
    && update-ca-certificates

# Install ttyd static binary (avoids libwebsockets issues).
# SHA256 pins from umrath/claude-hass-app — verify the binary before chmod+x
# so a compromised GitHub release can't ship us a different binary silently.
ARG BUILD_ARCH
RUN case "${BUILD_ARCH}" in \
        amd64)   TTYD_ARCH="x86_64";  TTYD_SHA256="8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55" ;; \
        aarch64) TTYD_ARCH="aarch64"; TTYD_SHA256="b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165" ;; \
        *) echo "Unsupported arch: ${BUILD_ARCH}" && exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${TTYD_ARCH}" -o /usr/bin/ttyd && \
    echo "${TTYD_SHA256}  /usr/bin/ttyd" | sha256sum -c - && \
    chmod +x /usr/bin/ttyd

# Install Claude Code via npm into /opt/npm-global (image-baked staging path).
# At runtime the boot script seeds /data/npm-global from this path on first
# boot, and `npm install -g ...@latest` writes to /data/npm-global, which is
# writable under the AppArmor profile and persists across restarts (issue #13).
RUN NPM_CONFIG_PREFIX=/opt/npm-global npm install -g @anthropic-ai/claude-code

# Install hass-mcp for Home Assistant integration
RUN pip3 install --no-cache-dir --break-system-packages hass-mcp

# Install mbpoll (Modbus command line tool) from source.
# Pinned to v1.5.4 — building from a moving `main` is a supply-chain risk.
RUN apk add --no-cache --virtual .build-deps \
    build-base \
    cmake \
    libmodbus-dev \
    && git clone --depth 1 --branch v1.5.4 https://github.com/epsilonrt/mbpoll.git /tmp/mbpoll \
    && cd /tmp/mbpoll \
    && mkdir build && cd build \
    && cmake .. \
    && make \
    && make install \
    && cd / \
    && rm -rf /tmp/mbpoll \
    && apk del .build-deps \
    && apk add --no-cache libmodbus

ENV NPM_CONFIG_CACHE=/root/.npm

# Install Home Assistant CLI (ha command)
RUN case "${BUILD_ARCH}" in \
        amd64) HA_ARCH="amd64" ;; \
        aarch64) HA_ARCH="aarch64" ;; \
        armv7|armhf) HA_ARCH="armhf" ;; \
        i386) HA_ARCH="i386" ;; \
        *) HA_ARCH="amd64" ;; \
    esac && \
    curl -fsSL "https://github.com/home-assistant/cli/releases/latest/download/ha_${HA_ARCH}" -o /usr/local/bin/ha && \
    chmod +x /usr/local/bin/ha

# Create necessary directories (NOT /root/.claude - will be symlinked at runtime)
RUN mkdir -p \
    /homeassistant \
    /root/.config \
    /root/.local/bin

# Configure tmux with sane defaults for the HA web terminal
# - 5000 line history (lower than 20000 to avoid OOM kills on small VMs)
# - bracketed paste enabled so OAuth tokens paste cleanly without enter-on-newline
# - mouse on for scroll, but xterm-keys to keep modifier shortcuts working
# Shipped as a static file and COPYed in rather than written with a heredoc:
# heredoc syntax needs a `# syntax=docker/dockerfile` frontend, and without it
# older Docker parsers fail the build with "unknown instruction: set" (issue #26).
COPY rootfs/root/.tmux.conf /root/.tmux.conf

# Configure bash with aliases and prompt. COPYed rather than written with a
# heredoc, for the same build-portability reason as .tmux.conf above (issue #26).
COPY rootfs/root/.bashrc /root/.bashrc

# Privileged-action boundary (issue #29): a PreToolUse hook that blocks or gates
# destructive Home Assistant actions (stop Core, disable watchdog, reboot host,
# OS update, restart) and a boot-time configurator that wires it into the Claude
# Code settings from the app options. Shipped as static rootfs scripts and made
# executable so they run under the AppArmor profile (/usr/local/** is ixr).
COPY rootfs/usr/local/bin/ha-privileged-guard.sh /usr/local/bin/ha-privileged-guard.sh
COPY rootfs/usr/local/bin/ha-guard-configure.sh /usr/local/bin/ha-guard-configure.sh
RUN chmod +x /usr/local/bin/ha-privileged-guard.sh /usr/local/bin/ha-guard-configure.sh

# Ensure .bashrc is sourced for login shells too
RUN echo 'source ~/.bashrc' > /root/.profile

# Set up PATH and runtime npm prefix.
# NPM_CONFIG_PREFIX moves `npm install -g` writes off the read-only /usr/local
# tree (which the AppArmor profile denies) to /data/npm-global (rwk, persistent).
# /data/npm-global/bin comes first in PATH so a user-updated `claude` wins over
# the image-bundled copy at /opt/npm-global/bin. See issue #13.
ENV NPM_CONFIG_PREFIX=/data/npm-global \
    PATH="/data/npm-global/bin:/opt/npm-global/bin:/root/.local/bin:${PATH}"

# Set working directory
WORKDIR /homeassistant

# Health check - long start-period because npm update on slow VMs can take >30s
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD curl -sf http://localhost:7681/ || exit 1

# Startup script that reads config and persists Claude auth
# Use /homeassistant/.claudecode which is always persistent
ENTRYPOINT []
CMD ["/bin/bash", "-c", "\
  export HA_TOKEN=\"$SUPERVISOR_TOKEN\" && \
  export HA_URL=\"http://supervisor/core\" && \
  PERSIST_DIR=/homeassistant/.claudecode && \
  mkdir -p $PERSIST_DIR/config /root/.config && \
  printf '%s\n' \
    '# Claude Code - Home Assistant App' \
    '' \
    '## Path Mapping' \
    '' \
    'In this app container, paths are mapped differently than HA Core:' \
    '- \\`/homeassistant\\` = HA config directory (equivalent to \\`/config\\` in HA Core)' \
    '- \\`/config\\` does NOT exist - always use \\`/homeassistant\\`' \
    '' \
    'When users mention \\`/config/...\\`, translate to \\`/homeassistant/...\\`' \
    '' \
    '## Available Paths' \
    '' \
    '| Path | Description | Access |' \
    '|------|-------------|--------|' \
    '| \\`/homeassistant\\` | HA configuration | read-write |' \
    '| \\`/share\\` | Shared folder | read-write |' \
    '| \\`/media\\` | Media files | read-write |' \
    '| \\`/ssl\\` | SSL certificates | read-only |' \
    '| \\`/backup\\` | Backups | read-only |' \
    '' \
    '## Home Assistant Integration' \
    '' \
    'Use the \\`homeassistant\\` MCP server to query entities and call services.' \
    '' \
    '## Reading Home Assistant Logs' \
    '' \
    '**Log levels (from most to least verbose):**' \
    '- \\`debug\\` - Only shown if explicitly enabled in configuration.yaml' \
    '- \\`info\\` - General information, shown by default' \
    '- \\`warning\\` - Warnings, always shown' \
    '- \\`error\\` - Errors, always shown' \
    '' \
    '**Commands to read logs:**' \
    '\\`\\`\\`bash' \
    '# View recent logs (ha CLI)' \
    'ha core logs 2>&1 | tail -100' \
    '' \
    '# Filter by keyword' \
    'ha core logs 2>&1 | grep -i keyword' \
    '' \
    '# Filter errors only' \
    'ha core logs 2>&1 | grep -iE \"(error|exception)\"' \
    '' \
    '# Alternative: read log file directly' \
    'tail -100 /homeassistant/home-assistant.log' \
    '\\`\\`\\`' \
    '' \
    '**To enable debug logging for an integration**, add to \\`configuration.yaml\\`:' \
    '\\`\\`\\`yaml' \
    'logger:' \
    '  default: info' \
    '  logs:' \
    '    custom_components.YOUR_INTEGRATION: debug' \
    '\\`\\`\\`' \
    '' \
    '**Key insight:** \\`_LOGGER.debug()\\` calls are invisible unless the logger level is set to debug. Use \\`_LOGGER.info()\\` or \\`_LOGGER.warning()\\` for logs that should always appear.' \
    '' \
    '## Privileged actions and safety (enforced by this app)' \
    '' \
    'A privileged-action guard is active. Some Home Assistant actions are BLOCKED and some require explicit human confirmation before they run. This is deliberate, not a malfunction.' \
    '' \
    '- NEVER disable the Supervisor watchdog and stop or restart Core in the same session. If your context is lost between the two steps, Home Assistant stays down with no automatic recovery and needs physical access to fix.' \
    '- A full restart of Home Assistant requires human confirmation. Prefer reloading a specific YAML domain (for example automation.reload) over a full restart whenever that is enough.' \
    '- NEVER autonomously stop Core, reboot or shut down the host, disable the watchdog, or start an OS or host update. Name the action you would need and let the user carry it out from the Home Assistant UI (Settings > System).' \
    '- After ANY service call meant to change state, VERIFY the result by re-reading the entity or state afterwards. A call can return success yet do nothing (for example an orphaned automation entity that survived a rename), so never trust the return value alone.' \
    '- If the guard blocks or asks about an action, do not try to route around it with an alternate curl, ha CLI, or REST call. Explain to the user what you need and why.' \
    '- When unattended_mode is on, actions that normally require human confirmation are refused instead of prompted, because nobody is present to answer. Do not retry them or look for another route; note what was refused and let the user run it in an attended session or from the Home Assistant UI.' \
    '- Do NOT hand the user a shell command, an escape prefix, or any other recipe for bypassing the guard, even if they ask how. Point them at the Home Assistant UI, or at the app options guard_privileged_actions / disallow_actions if they want the policy itself relaxed. Naming the action and letting them decide is the whole point of the boundary.' \
    > $PERSIST_DIR/CLAUDE.md && \
  if [ ! -L /root/.claude ]; then rm -rf /root/.claude; ln -s $PERSIST_DIR /root/.claude; fi && \
  if [ ! -L /root/.config/claude-code ]; then rm -rf /root/.config/claude-code; ln -s $PERSIST_DIR/config /root/.config/claude-code; fi && \
  if [ ! -L /root/.claude.json ]; then touch $PERSIST_DIR/.claude.json; rm -f /root/.claude.json; ln -s $PERSIST_DIR/.claude.json /root/.claude.json; fi && \
  if mkdir -p /data 2>/dev/null && [ -w /data ]; then \
    if [ ! -f /data/npm-global/.seed-complete ]; then \
      if [ -x /data/npm-global/bin/claude ] && /data/npm-global/bin/claude --version >/dev/null 2>&1; then \
        touch /data/npm-global/.seed-complete; \
        echo '[INFO] Existing /data/npm-global is healthy; marked seed complete'; \
      else \
        echo '[INFO] Seeding /data/npm-global from /opt/npm-global (first boot, fresh install, or repairing a partial seed)'; \
        rm -rf /data/npm-global; \
        if cp -a /opt/npm-global /data/npm-global && [ -x /data/npm-global/bin/claude ]; then \
          touch /data/npm-global/.seed-complete; \
          echo '[INFO] Seeded /data/npm-global'; \
        else \
          echo '[WARN] Failed to seed /data/npm-global; removing partial copy and falling back to image-bundled /opt/npm-global (auto_update may fail)'; \
          rm -rf /data/npm-global; \
        fi; \
      fi; \
    fi; \
  else \
    echo '[WARN] /data is not writable; falling back to image-bundled /opt/npm-global (auto_update will fail)'; \
  fi && \
  FONT_SIZE=$(jq -r '.terminal_font_size // 14' /data/options.json) && \
  case $FONT_SIZE in *[!0-9]*|'') FONT_SIZE=14;; esac && \
  THEME=$(jq -r '.terminal_theme // \"dark\"' /data/options.json) && \
  SESSION_PERSIST=$(jq -r '.session_persistence // false' /data/options.json) && \
  AUTO_CONTINUE=$(jq -r '.auto_continue // false' /data/options.json) && \
  ENABLE_MCP=$(jq -r 'if .enable_mcp == false then false else true end' /data/options.json) && \
  UNATTENDED_MODE=$(jq -r 'if .unattended_mode == true then true else false end' /data/options.json) && \
  if [ \"$UNATTENDED_MODE\" = \"true\" ]; then \
    export IS_SANDBOX=1 HA_GUARD_UNATTENDED=1; \
    echo '[INFO] Unattended mode: IS_SANDBOX=1 exported for this session'; \
    echo '[INFO] Unattended mode: HA_GUARD_UNATTENDED=1 exported for the privileged-action guard'; \
    if [ \"$(jq -r 'if .guard_privileged_actions == false then true else false end' /data/options.json)\" = \"true\" ]; then \
      echo '[WARN] unattended_mode is on while guard_privileged_actions is off: Claude runs as root with no permission prompts and no guard. This combination is not recommended; turn the guard back on.'; \
    fi; \
  fi && \
  AUTO_UPDATE=$(jq -r '.auto_update_claude // false' /data/options.json) && \
  UPDATE_TIMEOUT=$(jq -r '.claude_update_timeout // 300' /data/options.json) && \
  WORK_DIR=$(jq -r '.working_directory // empty' /data/options.json) && \
  { [ -n \"$WORK_DIR\" ] || WORK_DIR=/homeassistant; } && \
  if [ ! -d \"$WORK_DIR\" ]; then \
    echo \"[WARN] working_directory '$WORK_DIR' does not exist - falling back to /homeassistant\"; \
    WORK_DIR=/homeassistant; \
  fi && \
  SETTINGS_FILE=/root/.claude/settings.json && \
  CLAUDE_JSON=/root/.claude.json && \
  mkdir -p \"$(dirname \"$SETTINGS_FILE\")\" && \
  { [ -s \"$SETTINGS_FILE\" ] || echo '{}' > \"$SETTINGS_FILE\"; } && \
  if ! jq -e . \"$SETTINGS_FILE\" >/dev/null 2>&1; then \
    SETTINGS_BAK=\"$SETTINGS_FILE.corrupt.$(date +%s)\"; \
    cp -f \"$SETTINGS_FILE\" \"$SETTINGS_BAK\" 2>/dev/null || true; \
    echo '{}' > \"$SETTINGS_FILE\"; \
    echo \"[ERROR] $SETTINGS_FILE was not valid JSON; backed it up to $SETTINGS_BAK and reset it so this boot's settings edits can run instead of silently failing one by one. Re-merge any custom settings from the backup.\"; \
  fi && \
  { [ -s \"$CLAUDE_JSON\" ] || echo '{}' > \"$CLAUDE_JSON\"; } && \
  if jq -e 'has(\"mcpServers\")' \"$SETTINGS_FILE\" >/dev/null 2>&1; then \
    if jq 'del(.mcpServers)' \"$SETTINGS_FILE\" > /tmp/settings.nomcp 2>/dev/null && jq -e . /tmp/settings.nomcp >/dev/null 2>&1; then \
      mv /tmp/settings.nomcp \"$SETTINGS_FILE\" && \
      echo '[INFO] Removed a stray mcpServers key from settings.json (MCP servers belong in .claude.json)'; \
    else \
      rm -f /tmp/settings.nomcp; \
    fi; \
  fi && \
  STALE_RULES=$(jq -r '[(.permissions.allow // [])[] | select((type == \"string\") and (startswith(\"Glob(\") or startswith(\"Grep(\")))] | join(\", \")' \"$SETTINGS_FILE\" 2>/dev/null || echo '') && \
  if [ -n \"$STALE_RULES\" ]; then \
    if jq '.permissions.allow = [ (.permissions.allow // [])[] | select((((type == \"string\") and (startswith(\"Glob(\") or startswith(\"Grep(\")))) | not) ]' \"$SETTINGS_FILE\" > /tmp/settings.prune 2>/dev/null && jq -e . /tmp/settings.prune >/dev/null 2>&1; then \
      mv /tmp/settings.prune \"$SETTINGS_FILE\" && \
      echo \"[INFO] Removed deprecated permission rules that stop Claude Code launching: $STALE_RULES\"; \
    else \
      rm -f /tmp/settings.prune; \
      echo '[WARN] Failed to remove deprecated Glob()/Grep() permission rules from settings.json'; \
    fi; \
  fi && \
  if [ \"$ENABLE_MCP\" = \"true\" ]; then \
    if jq '.mcpServers.homeassistant = {\"type\":\"stdio\",\"command\":\"hass-mcp\"} | del(.mcpServers.playwright)' \"$CLAUDE_JSON\" > /tmp/claude.tmp && jq -e . /tmp/claude.tmp >/dev/null 2>&1; then \
      cp /tmp/claude.tmp \"$PERSIST_DIR/.claude.json.tmp\" && mv \"$PERSIST_DIR/.claude.json.tmp\" \"$PERSIST_DIR/.claude.json\"; \
    else \
      echo '[WARN] Failed to register MCP server in .claude.json'; \
    fi; \
    rm -f /tmp/claude.tmp; \
    ALLOWED_TOOLS='[\"mcp__homeassistant__get_version\",\"mcp__homeassistant__get_entity\",\"mcp__homeassistant__list_entities\",\"mcp__homeassistant__search_entities_tool\",\"mcp__homeassistant__domain_summary_tool\",\"mcp__homeassistant__list_automations\",\"mcp__homeassistant__get_history\",\"mcp__homeassistant__get_error_log\",\"Read(/homeassistant/**)\",\"Read(/config/**)\",\"Read(/share/**)\",\"Read(/media/**)\"]' && \
    if jq --argjson tools \"$ALLOWED_TOOLS\" '.permissions.allow = ($tools + (.permissions.allow // []) | unique)' \"$SETTINGS_FILE\" > /tmp/settings.tmp; then \
      mv /tmp/settings.tmp \"$SETTINGS_FILE\" && \
      echo '[INFO] MCP configured with Home Assistant integration' && \
      echo '[INFO] Pre-authorized read-only MCP tools'; \
    else \
      echo '[WARN] Failed to write pre-authorized tools to settings.json - read tools will require manual approval on first use'; \
    fi; \
  else \
    echo '[INFO] MCP disabled'; \
  fi && \
  { bash /usr/local/bin/ha-guard-configure.sh \"$SETTINGS_FILE\" || echo '[WARN] privileged-action guard configuration failed'; } && \
  SIDECAR=\"$PERSIST_DIR/.defaultmode-before-unattended\" && \
  if [ \"$UNATTENDED_MODE\" = \"true\" ]; then \
    CLI_BIN=$(command -v claude 2>/dev/null || echo /data/npm-global/bin/claude); \
    CLI_REAL=$(readlink -f \"$CLI_BIN\" 2>/dev/null || echo \"$CLI_BIN\"); \
    if [ -e \"$CLI_REAL\" ] && ! grep -qs IS_SANDBOX \"$CLI_REAL\"; then \
      echo '[ERROR] The installed Claude Code CLI does not recognize the IS_SANDBOX override, so permissions.defaultMode: bypassPermissions would make it refuse to launch as root on every start. Leaving the normal prompting mode in place; unattended_mode is degraded until a CLI version that supports IS_SANDBOX is installed.'; \
      if jq -e '.permissions.defaultMode == \"bypassPermissions\"' \"$SETTINGS_FILE\" >/dev/null 2>&1; then \
        SAVED_MODE=''; \
        if [ -f \"$SIDECAR\" ]; then SAVED_MODE=$(cat \"$SIDECAR\" 2>/dev/null || echo ''); fi; \
        case \"$SAVED_MODE\" in default|acceptEdits|plan) ;; *) SAVED_MODE='';; esac; \
        if [ -n \"$SAVED_MODE\" ] && jq --arg m \"$SAVED_MODE\" '.permissions.defaultMode = $m' \"$SETTINGS_FILE\" > /tmp/settings.unattended 2>/dev/null && jq -e . /tmp/settings.unattended >/dev/null 2>&1; then \
          mv /tmp/settings.unattended \"$SETTINGS_FILE\" && rm -f \"$SIDECAR\" && \
          echo \"[ERROR] Removed the permissions.defaultMode: bypassPermissions an earlier boot wrote and restored your previous permissions.defaultMode: $SAVED_MODE, so the session can still launch\"; \
        elif jq 'del(.permissions.defaultMode)' \"$SETTINGS_FILE\" > /tmp/settings.unattended 2>/dev/null && jq -e . /tmp/settings.unattended >/dev/null 2>&1; then \
          mv /tmp/settings.unattended \"$SETTINGS_FILE\" && rm -f \"$SIDECAR\" && \
          echo '[ERROR] Removed the permissions.defaultMode: bypassPermissions an earlier boot wrote, so the session can still launch'; \
        else rm -f /tmp/settings.unattended; fi; \
      fi; \
    else \
      PREV_MODE=$(jq -r '.permissions.defaultMode // empty' \"$SETTINGS_FILE\" 2>/dev/null || echo ''); \
      if [ -n \"$PREV_MODE\" ] && [ \"$PREV_MODE\" != \"bypassPermissions\" ]; then \
        printf '%s' \"$PREV_MODE\" > \"$SIDECAR\"; \
        echo \"[WARN] Unattended mode replaced your permissions.defaultMode: $PREV_MODE (it will be restored when unattended_mode is turned off)\"; \
      fi; \
      if jq '.permissions = (.permissions // {}) | .permissions.defaultMode = \"bypassPermissions\"' \"$SETTINGS_FILE\" > /tmp/settings.unattended 2>/dev/null && jq -e . /tmp/settings.unattended >/dev/null 2>&1; then \
        mv /tmp/settings.unattended \"$SETTINGS_FILE\" && \
        echo '[INFO] Unattended mode: permissions.defaultMode set to bypassPermissions'; \
      else \
        rm -f /tmp/settings.unattended; \
        echo '[WARN] Failed to set permissions.defaultMode for unattended mode'; \
      fi; \
    fi; \
  elif jq -e '.permissions.defaultMode == \"bypassPermissions\"' \"$SETTINGS_FILE\" >/dev/null 2>&1; then \
    SAVED_MODE=''; \
    if [ -f \"$SIDECAR\" ]; then SAVED_MODE=$(cat \"$SIDECAR\" 2>/dev/null || echo ''); fi; \
    case \"$SAVED_MODE\" in default|acceptEdits|plan) ;; *) SAVED_MODE='';; esac; \
    if [ -n \"$SAVED_MODE\" ] && jq --arg m \"$SAVED_MODE\" '.permissions.defaultMode = $m' \"$SETTINGS_FILE\" > /tmp/settings.unattended 2>/dev/null && jq -e . /tmp/settings.unattended >/dev/null 2>&1; then \
      mv /tmp/settings.unattended \"$SETTINGS_FILE\" && \
      echo \"[INFO] Unattended mode off: restored your previous permissions.defaultMode: $SAVED_MODE\"; \
    elif jq 'del(.permissions.defaultMode)' \"$SETTINGS_FILE\" > /tmp/settings.unattended 2>/dev/null && jq -e . /tmp/settings.unattended >/dev/null 2>&1; then \
      mv /tmp/settings.unattended \"$SETTINGS_FILE\" && \
      echo '[INFO] Unattended mode off: removed a stale permissions.defaultMode: bypassPermissions (from a previous boot, or hand-edited) so the session does not hit the root/bypassPermissions launch failure'; \
    else \
      rm -f /tmp/settings.unattended; \
    fi; \
    rm -f \"$SIDECAR\"; \
  else \
    rm -f \"$SIDECAR\"; \
  fi && \
  if [ \"$AUTO_UPDATE\" = \"true\" ]; then \
    UPDATE_LOG=/tmp/claude-update.log; \
    echo \"[INFO] Updating Claude Code in background (timeout ${UPDATE_TIMEOUT}s)...\"; \
    ( echo \"--- $(date -u +%Y-%m-%dT%H:%M:%SZ) starting npm install -g @anthropic-ai/claude-code@latest (timeout ${UPDATE_TIMEOUT}s) ---\" >> \"$UPDATE_LOG\"; \
      if timeout \"$UPDATE_TIMEOUT\" npm install -g @anthropic-ai/claude-code@latest >> \"$UPDATE_LOG\" 2>&1; then \
        echo '[INFO] Claude Code update finished'; \
      else \
        rc=$?; \
        echo \"[WARN] Claude Code update failed/timed out (exit $rc, see $UPDATE_LOG). Last lines:\"; \
        tail -n 10 \"$UPDATE_LOG\" 2>/dev/null | sed 's/^/  | /'; \
      fi ) & \
  else \
    echo '[INFO] auto_update_claude disabled - skipping update'; \
  fi; \
  if [ \"$THEME\" = \"dark\" ]; then \
    COLORS='background=#1e1e2e,foreground=#cdd6f4,cursor=#f5e0dc'; \
  else \
    COLORS='background=#eff1f5,foreground=#4c4f69,cursor=#dc8a78'; \
  fi && \
  if [ \"$SESSION_PERSIST\" = \"true\" ]; then \
    if [ \"$AUTO_CONTINUE\" = \"true\" ]; then \
      SHELL_CMD=(tmux new-session -A -s claude 'bash -ic cc'); \
    else \
      SHELL_CMD=(tmux new-session -A -s claude); \
    fi; \
  else \
    SHELL_CMD=(bash --login); \
  fi && \
  cd \"$WORK_DIR\" && \
  exec ttyd --port 7681 --writable --ping-interval 30 --max-clients 5 \
    -t fontSize=$FONT_SIZE \
    -t fontFamily=Monaco,Consolas,monospace \
    -t scrollback=20000 \
    -t \"theme=$COLORS\" \
    \"${SHELL_CMD[@]}\" \
"]
