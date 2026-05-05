# Claude Code for Home Assistant

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Anthropic's AI-powered coding assistant, directly in your Home Assistant sidebar with full access to your configuration.

## Quick Start

```bash
claude "List all my automations"
claude "Turn off all lights in the living room"
claude "Create an automation to turn on lights at sunset"
claude "Why isn't my motion sensor automation working?"
```

## Requirements

- Home Assistant OS or Supervised installation
- [Anthropic account](https://console.anthropic.com/) (authentication handled in terminal)

## Features

- **Web Terminal**: Access Claude Code through a browser-based terminal
- **Config Access**: Read and write Home Assistant configuration files
- **hass-mcp Integration**: Direct control of HA entities and services
- **Session Persistence**: Optional tmux integration to preserve sessions across page refreshes
- **Customizable Theme**: Choose between dark and light terminal themes
- **Multi-Architecture**: Supports amd64, aarch64, armv7, armhf, and i386
- **Secure Authentication**: Claude Code handles its own authentication securely

## Setup

### 1. Install the Add-on

1. Add the repository to Home Assistant
2. Install the "Claude Code" add-on
3. Start the add-on
4. Open the Web UI from the sidebar

### 2. Authenticate with Claude Code

On first launch, Claude Code will prompt you to authenticate:

1. Open the terminal from the HA sidebar
2. Type `claude` to start
3. Follow the authentication prompts
4. Your credentials are stored securely by Claude Code

**Note**: The add-on does NOT require you to enter API keys in the configuration. Claude Code handles authentication itself, storing credentials securely in its own configuration directory. This is more secure than storing keys in Home Assistant's add-on config.

## Using Claude Code

### Basic Usage

Once authenticated, Claude Code is ready to help with:

- Editing Home Assistant YAML configurations
- Creating automations and scripts
- Debugging configuration issues
- Writing custom integrations

### Home Assistant Integration

With hass-mcp enabled, Claude can:

- Query entity states: "What's the temperature in the living room?"
- Control devices: "Turn off all lights in the bedroom"
- List services: "What services are available for climate control?"
- Debug automations: "Why didn't my morning routine trigger?"

### Example Commands

```bash
# Start interactive session
claude

# One-off commands
claude "Add a new automation that turns on the porch light at sunset"
claude "Check my configuration.yaml for errors"
claude "List all unavailable entities"

# Continue previous conversation
claude --continue
```

### Keyboard Shortcuts

| Shortcut | Command |
|----------|---------|
| `c` | `claude` |
| `cc` | `claude --continue` |
| `ha-config` | Navigate to config directory |
| `ha-logs` | View Home Assistant logs |

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `enable_mcp` | Enable HA integration | true |
| `terminal_font_size` | Font size (10-24) | 14 |
| `terminal_theme` | dark or light | dark |
| `working_directory` | Start directory | /homeassistant |
| `session_persistence` | Use tmux for persistent sessions | false |
| `auto_update_claude` | Auto-update Claude Code on startup (runs in background, with timeout) | false |

> **Note:** `session_persistence` and `auto_update_claude` both default to `false` to keep startup fast and prevent OOM kills on small VMs (e.g. Proxmox HAOS with limited RAM). Turn them on if you want long-running sessions across reconnects or always-latest Claude Code.

## File Locations

| Path | Description | Access |
|------|-------------|--------|
| `/homeassistant` | HA configuration directory | read-write |
| `/share` | Shared folder | read-write |
| `/media` | Media folder | read-write |
| `/ssl` | SSL certificates | read-only |
| `/backup` | Backups | read-only |

## Session Persistence

When `session_persistence` is enabled, the add-on uses tmux to maintain your terminal session. This means:

- Your session survives browser refreshes
- You can disconnect and reconnect without losing context
- Claude Code conversations are preserved

### tmux Commands

If you're new to tmux:

| Key | Action |
|-----|--------|
| `Ctrl+b d` | Detach from session (keeps it running) |
| `Ctrl+b [` | Enter scroll/copy mode (use arrow keys) |
| Mouse wheel | Scroll up/down (auto-enters copy mode) |
| `q` | Exit scroll/copy mode |

### Copy and Paste in tmux

Since tmux captures mouse events, copy/paste works differently:

| Action | How to do it |
|--------|--------------|
| **Copy** | Hold `Ctrl+Shift` while selecting text with mouse |
| **Paste** | `Shift+Insert` or middle-click |
| **Alternative paste** | `Ctrl+Shift+V` (browser dependent) |

**Note**: Regular right-click paste and simple mouse selection won't work because tmux intercepts these events for scrolling.

#### Authenticating Claude Code (first launch)

The authentication URL can be long and may wrap across multiple lines. To handle this:

1. **Zoom out** your browser (`Ctrl + -` or `Cmd + -`) until the URL fits on a single line
2. **Click the link** — it should open in a new tab
3. Complete authentication in the browser and **copy the auth code**
4. Click back on the terminal and **paste** with `Shift+Insert` or `Ctrl+Shift+V`

If clicking the link doesn't work, hold `Ctrl+Shift` while selecting the URL with your mouse to copy it, then paste it into your browser's address bar.

### Scrolling and Session Persistence Trade-offs

**With tmux (`session_persistence: true`):**
- ✅ Session survives browser refresh/disconnect
- ✅ Can detach and reattach to running sessions
- ✅ Long-running Claude tasks continue in background
- ✅ Mouse wheel scrolling works (enters copy mode automatically)
- ✅ 5,000 line scrollback buffer
- ⚠️ Use middle-click or Shift+Insert to paste (right-click paste may not work)

**Without tmux (`session_persistence: false`, default):**
- ✅ Native browser scrolling
- ✅ Simpler terminal behavior
- ✅ Standard copy/paste behavior — easier OAuth auth code paste
- ❌ Session lost on browser refresh
- ❌ Session lost if add-on restarts

**Recommendation:**
- Default `session_persistence: false` is best for first-time setup — copy/paste during the OAuth flow is far less fiddly without tmux.
- Switch to `session_persistence: true` once you're authenticated and want long-running sessions to survive disconnects.

## Security

### Authentication
- **No API keys in add-on config**: Claude Code handles authentication itself
- Credentials are stored securely in Claude Code's own directory (`~/.claude/`)
- This is more secure than storing keys in Home Assistant's configuration

### Container Security
- The Supervisor token is automatically managed and not exposed
- File access is limited to mapped directories
- The add-on runs in an isolated container

## Troubleshooting

### Authentication issues

Claude Code manages its own authentication. If you have issues:
1. Type `claude` to start the authentication flow
2. Follow the prompts to log in or enter your API key
3. Credentials are saved automatically for future sessions

**Can't copy the URL or paste the auth code?** The terminal uses tmux, which changes how copy/paste works. See [Copy and Paste in tmux](#copy-and-paste-in-tmux) for instructions.

### hass-mcp not working

1. Verify `enable_mcp` is true in configuration
2. Check add-on logs for connection errors
3. Restart the add-on after configuration changes

### Terminal not loading

1. Check that the add-on is running (green indicator)
2. Try refreshing the page
3. Check browser console for errors
4. Review add-on logs for ttyd errors

### Session not persisting

1. Ensure `session_persistence` is set to `true` (default is `false` in 1.2.64+)
2. The session is named "claude" — it will auto-attach on reconnect

### Configuration changes not applying

After changing configuration:
1. Save the configuration
2. Restart the add-on completely

### Add-on is killed on startup ("Killed" in logs)

Reported on Proxmox HAOS and other small-VM setups. The container starts, ttyd comes up, but `claude` or `npm` get killed by the OOM killer mid-boot.

Mitigations applied in this fork (1.2.64+):
- `auto_update_claude` defaults to **false** so npm doesn't run a global install on every restart
- When auto-update is enabled, it runs in the background with a 90s timeout and a 512 MB Node heap cap (`NODE_OPTIONS=--max-old-space-size=512`)
- tmux scrollback reduced from 20,000 → 5,000 lines
- Healthcheck `start-period` raised to 120s so Supervisor doesn't restart the addon while it's still booting

If you still see kills:
1. Increase the VM's RAM (2 GB+ recommended)
2. Keep `auto_update_claude: false` and update manually with `npm install -g @anthropic-ai/claude-code@latest`
3. Set `session_persistence: false`

### `npm update` never picks up new Claude Code versions

Earlier versions used `npm update -g`, which is buggy for global packages and often left users stuck on the originally-installed version. This fork now uses `npm install -g @anthropic-ai/claude-code@latest` (when `auto_update_claude: true`), which always pulls the latest published release.

You can also update manually from the terminal:

```bash
npm install -g @anthropic-ai/claude-code@latest
```

### Authentication: "400 error" or can't paste the auth code

The OAuth code is long. Common causes:
- The terminal has wrapped the auth URL across lines and you copied a partial code. Zoom out (`Ctrl+-`) until the URL fits on one line.
- tmux is intercepting the paste. Use `Shift+Insert` (or middle-click) — `Ctrl+V` does not work in the terminal.
- The code expired. Re-run `claude` to get a fresh URL.

## Support

- [GitHub Issues](https://github.com/sproft/hass-claude/issues)
- [Home Assistant Community](https://community.home-assistant.io/)
