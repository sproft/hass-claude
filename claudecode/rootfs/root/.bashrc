export TERM=xterm-256color
export LANG=C.UTF-8

# A login shell (what the web terminal opens via `bash --login` or tmux) sources
# /etc/profile first, and on the Alpine base that resets PATH to a fixed default
# that excludes the npm global prefixes. Re-add them here so `claude` (installed
# under /data/npm-global or /opt/npm-global since 1.2.70, issues #15/#16) stays on
# PATH. .bashrc is sourced after /etc/profile via ~/.profile, so this prepend wins.
export PATH="/data/npm-global/bin:/opt/npm-global/bin:/root/.local/bin:$PATH"
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
