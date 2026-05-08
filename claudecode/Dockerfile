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
    docker-cli \
    && update-ca-certificates

# Install ttyd static binary (avoids libwebsockets issues)
ARG BUILD_ARCH
RUN case "${BUILD_ARCH}" in \
        amd64) TTYD_ARCH="x86_64" ;; \
        aarch64) TTYD_ARCH="aarch64" ;; \
        armv7|armhf) TTYD_ARCH="armhf" ;; \
        i386) TTYD_ARCH="i686" ;; \
        *) TTYD_ARCH="x86_64" ;; \
    esac && \
    curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${TTYD_ARCH}" -o /usr/bin/ttyd && \
    chmod +x /usr/bin/ttyd

# Install Claude Code via npm
RUN npm install -g @anthropic-ai/claude-code

# Install hass-mcp for Home Assistant integration and pymodbus for Modbus operations
RUN pip3 install --no-cache-dir --break-system-packages hass-mcp pymodbus pyserial

# Install mbpoll (Modbus command line tool) from source
RUN apk add --no-cache --virtual .build-deps \
    build-base \
    cmake \
    libmodbus-dev \
    && git clone https://github.com/epsilonrt/mbpoll.git /tmp/mbpoll \
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
RUN cat > /root/.tmux.conf << 'EOF'
set -g history-limit 5000
set -ga terminal-overrides ',xterm*:smcup@:rmcup@'
set -g mouse on
set -g xterm-keys on
set -s set-clipboard on
# Bracketed paste: tmux >= 3.2 enables this by default; force it for older builds
set -g allow-passthrough on
bind -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" "send-keys -M" "if -Ft= '#{pane_in_mode}' 'send-keys -M' 'select-pane -t=; copy-mode -e; send-keys -M'"
bind -n WheelDownPane select-pane -t= \; send-keys -M
EOF

# Configure bash with aliases and prompt
RUN cat > /root/.bashrc << 'EOF'
export TERM=xterm-256color
export LANG=C.UTF-8
PS1='\[\033[1;36m\]claude-code\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ '

# Function to update MCP token before starting Claude
update_mcp_token() {
  local SETTINGS_FILE=/root/.claude/settings.json
  if [ -f "$SETTINGS_FILE" ] && [ -n "$SUPERVISOR_TOKEN" ]; then
    jq ".mcpServers.homeassistant.env.HASS_TOKEN = \"$SUPERVISOR_TOKEN\"" "$SETTINGS_FILE" > /tmp/settings.tmp 2>/dev/null && mv /tmp/settings.tmp "$SETTINGS_FILE"
  fi
}

# Aliases
alias ll='ls -la'
alias c='update_mcp_token && claude'
alias cc='update_mcp_token && claude --continue'
alias ha-config='cd /homeassistant'
alias ha-logs='cat /homeassistant/home-assistant.log 2>/dev/null || echo "Log not found"'
EOF

# Ensure .bashrc is sourced for login shells too
RUN echo 'source ~/.bashrc' > /root/.profile

# Set up PATH
ENV PATH="/root/.local/bin:${PATH}"

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
    '# Claude Code - Home Assistant Add-on' \
    '' \
    '## Path Mapping' \
    '' \
    'In this add-on container, paths are mapped differently than HA Core:' \
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
    > $PERSIST_DIR/CLAUDE.md && \
  if [ ! -L /root/.claude ]; then rm -rf /root/.claude; ln -s $PERSIST_DIR /root/.claude; fi && \
  if [ ! -L /root/.config/claude-code ]; then rm -rf /root/.config/claude-code; ln -s $PERSIST_DIR/config /root/.config/claude-code; fi && \
  if [ ! -L /root/.claude.json ]; then touch $PERSIST_DIR/.claude.json; rm -f /root/.claude.json; ln -s $PERSIST_DIR/.claude.json /root/.claude.json; fi && \
  FONT_SIZE=$(jq -r '.terminal_font_size // 14' /data/options.json) && \
  THEME=$(jq -r '.terminal_theme // \"dark\"' /data/options.json) && \
  SESSION_PERSIST=$(jq -r '.session_persistence // false' /data/options.json) && \
  ENABLE_MCP=$(jq -r '.enable_mcp // true' /data/options.json) && \
  AUTO_UPDATE=$(jq -r '.auto_update_claude // false' /data/options.json) && \
  UPDATE_TIMEOUT=$(jq -r '.claude_update_timeout // 300' /data/options.json) && \
  SETTINGS_FILE=/root/.claude/settings.json && \
  CLAUDE_JSON=/root/.claude.json && \
  mkdir -p \"$(dirname \"$SETTINGS_FILE\")\" && \
  { [ -s \"$SETTINGS_FILE\" ] || echo '{}' > \"$SETTINGS_FILE\"; } && \
  { [ -s \"$CLAUDE_JSON\" ] || echo '{}' > \"$CLAUDE_JSON\"; } && \
  if [ \"$ENABLE_MCP\" = \"true\" ]; then \
    if jq '.mcpServers.homeassistant = {\"type\":\"stdio\",\"command\":\"hass-mcp\"} | del(.mcpServers.playwright)' \"$CLAUDE_JSON\" > /tmp/claude.tmp; then \
      mv /tmp/claude.tmp \"$CLAUDE_JSON\"; \
    else \
      echo '[WARN] Failed to register MCP server in .claude.json'; \
    fi; \
    ALLOWED_TOOLS='[\"mcp__homeassistant__get_version\",\"mcp__homeassistant__get_entity\",\"mcp__homeassistant__list_entities\",\"mcp__homeassistant__search_entities_tool\",\"mcp__homeassistant__domain_summary_tool\",\"mcp__homeassistant__list_automations\",\"mcp__homeassistant__get_history\",\"mcp__homeassistant__get_error_log\",\"Read(/homeassistant/**)\",\"Read(/config/**)\",\"Read(/share/**)\",\"Read(/media/**)\",\"Glob(/homeassistant/**)\",\"Glob(/config/**)\",\"Grep(/homeassistant/**)\",\"Grep(/config/**)\"]' && \
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
    SHELL_CMD='tmux new-session -A -s claude'; \
  else \
    SHELL_CMD='bash --login'; \
  fi && \
  cd /homeassistant && \
  exec ttyd --port 7681 --writable --ping-interval 30 --max-clients 5 \
    -t fontSize=$FONT_SIZE \
    -t fontFamily=Monaco,Consolas,monospace \
    -t scrollback=20000 \
    -t \"theme=$COLORS\" \
    $SHELL_CMD \
"]
