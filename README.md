# Claude Code for Home Assistant

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Anthropic's AI coding assistant, directly inside Home Assistant. Build automations, debug your config, and manage your smart home from a browser-based terminal in the HA sidebar.

## App

| App | Description |
|-----|-------------|
| [Claude Code](claudecode/) | AI assistant for automations, debugging, and smart home management |

## Installation

[![Add Repository](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fsproft%2Fhass-claude)

Or manually: **Settings** → **Apps** → **App Store** → **⋮** → **Repositories** → Add `https://github.com/sproft/hass-claude`

Then install **Claude Code** from the app store and start it.

> Home Assistant renamed "Add-ons" to "Apps" some months ago. The Supervisor URL slug `supervisor_add_addon_repository` above is the legacy identifier and still works; it has not been renamed upstream.

## Why this fork?

This repository is a **focused fork** of [robsonfelix/robsonfelix-hass-addons](https://github.com/robsonfelix/robsonfelix-hass-addons), built around a single idea:

> **People who just want Claude Code inside Home Assistant should be able to install it and have it work — even on small Proxmox HAOS VMs, even on first-time OAuth, even when a new Claude Code release ships.**

Several recurring problems were reported on the [Home Assistant Community thread](https://community.home-assistant.io/t/claude-code-for-home-assistant-ai-assistant-directly-in-your-ha/974883):

- The app getting **`Killed` repeatedly on startup** on Proxmox / small-VM setups (community thread posts 74, 75, 77)
- **Auto-update never picking up new Claude Code versions** (posts 11, 26, 33)
- **OAuth auth-code paste flow being miserable** — tmux intercepting paste, URLs wrapping across lines, `400` errors (posts 3, 4, 17, 19, 56, 61, 62, 65, 71)

This fork:

1. **Strips the repo down to the Claude Code app only** (the original `auto-monocle` Alexa camera bridge and the standalone `playwright-browser` app are not included here). They are great in their own right, but they are unrelated to running Claude Code in Home Assistant, and removing them shrinks the maintenance surface and the install footprint.
2. **Ships targeted fixes** for the issues above (defaults flipped to fast-startup-friendly values, npm runs in the background with a timeout, healthcheck `start-period` raised, tmux paste-friendly config). See [`claudecode/CHANGELOG.md`](claudecode/CHANGELOG.md) for the full list.

If you want the Monocle bridge or the separate Playwright Browser app, they remain available in the upstream repository.

## Thanks

Huge thanks to [**Robson Felix**](https://github.com/robsonfelix). The original Claude Code app is the foundation of everything in this repo, and this fork exists only because his work made the integration possible in the first place. The MIT [LICENSE](LICENSE) and copyright notice in this repo are his, preserved as required and as deserved.

## License

MIT License — see [LICENSE](LICENSE).
