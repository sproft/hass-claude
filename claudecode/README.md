# Claude Code for Home Assistant

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Anthropic's AI coding assistant, in a terminal inside your Home Assistant sidebar.

Claude can read and edit the files in your configuration folder, look up the live state of your entities, call services, and help you debug why an automation is not firing. You talk to it in plain language and it does the work in your actual setup.

Three things to know before you start:

- **It uses your own Claude account.** A Claude Pro or Max subscription, or an Anthropic API account with credits. Usage draws on your plan or is billed to you.
- **It has real access to your Home Assistant.** Read and write on your configuration folder, and the ability to call services. That is what makes it useful, and it is worth understanding before you install. See [What Claude can reach](#what-claude-can-reach).
- **Anyone who can sign in to your Home Assistant can use it.** The terminal is a shell on your system behind a sidebar icon. Think twice on an instance that is shared or reachable from the internet.

---

## Before you start

| You need | Notes |
|---|---|
| Home Assistant OS or Supervised | Container and Core installs cannot run apps |
| An `amd64` or `aarch64` machine | Intel/AMD or 64-bit ARM such as a Raspberry Pi 4/5 |
| 2 GB RAM or more | 1 GB machines can have the app killed while starting |
| Outbound internet | Claude runs in the cloud, not on your box |
| A Claude account | Pro/Max subscription, or API credits |

---

## Install

1. In Home Assistant, go to **Settings → Apps → App Store**.
2. Open the three-dot menu (top right) → **Repositories**, and add:
   `https://github.com/sproft/hass-claude`
3. Find **Claude Code** in the store and click **Install**.
4. Click **Start**.

The first start takes a minute or two while the app sets itself up. Once it is running, a **Claude Code** entry with a brain icon appears in your sidebar. The **Open Web UI** button on the app page goes to the same place.

What opens is a **terminal**, not a chat box. That is expected.

If you have not used one before: it is a text-only window. Click anywhere in it, type, and press Enter to send. There are no buttons, and the mouse mostly does nothing. Claude replies in the same window.

---

## Sign in

In the terminal, type this and press Enter:

```bash
c
```

**The first time, Claude asks you a few setup questions** before anything else. They are text menus, so the mouse will not work: move with the **up and down arrow keys** and press **Enter** to choose. It asks you to pick a colour theme, to confirm you trust the files in this folder (yes, it is your own configuration), and how you want to sign in. Choose the Claude account option if you have a Pro or Max subscription, or the API option if you are using credits.

Then it prints a long login URL. This is the step people most often get stuck on, so:

1. **Zoom your browser out** (`Ctrl` and `-`) until the whole URL sits on one line. If it is wrapped across lines you will copy a broken link.
2. **Click the link.** It opens in a new tab.
3. Sign in and **copy the code** it gives you.
4. Click back on the terminal and **paste it**. Normal `Ctrl+V` works by default.

Your credentials are saved, so this is a one-time step. They live inside your configuration folder, which means **they are included in your Home Assistant backups**. Treat a backup as containing your Claude login.

A free Claude account will not work here. Sign-in appears to succeed and then Claude refuses to answer, which looks like a bug but is a plan limit.

> Paste behaves differently if you turn on session persistence later. See [Keeping your session alive](#keeping-your-session-alive).

---

## Your first five minutes

**First, check Claude can actually see your house.** Type this at the Claude prompt:

> How many lights do I have, and how many are on right now?

Real numbers back means the Home Assistant connection is working. If it talks about files instead, see [Claude cannot see my entities](#claude-cannot-see-my-entities-or-call-services).

**Then try a few questions that only read, never change:**

> Which of my automations have not triggered in the last week?

> Why did my morning routine not run today?

> Show me every entity that is currently unavailable.

**Then let it change something small.** Claude asks for permission before it writes to a file, so nothing happens without your say-so:

> Add a comment at the top of my automations.yaml explaining what the file is for.

Claude shows you the change and then asks permission. That prompt is another arrow-key menu, roughly:

```
Do you want to make this edit to automations.yaml?
❯ 1. Yes
  2. Yes, and don't ask again this session
  3. No, and tell Claude what to do differently
```

Move with the arrow keys, press Enter. Choose **1** for now. Nothing is written to disk until you do. Option 2 stops the asking for the rest of that session only, so leave it alone until you trust the pattern.

Then confirm in the Home Assistant UI that the file looks right. Now you know the whole loop.

---

## Working safely

Claude is genuinely useful on a live system, which is exactly why a few habits are worth having.

**Take a backup before any big change.** Settings → System → Backups. This is the difference between an annoying evening and a lost one.

**Read what it proposes before approving.** Claude explains its changes. Skim them. It is right most of the time, not all of the time.

**Check your config before restarting.** Ask Claude to run a config check, or use Developer Tools → YAML → Check configuration. A restart with broken YAML is how Home Assistant fails to come back.

**Prefer a reload over a restart.** Reloading automations or scripts is instant and safe. A full restart costs a minute of downtime.

**To stop Claude mid-task, press `Esc`.** That interrupts whatever it is doing and hands the prompt back to you. Do not close the browser tab to stop it, since that leaves the job half-done.

### The built-in safety guard

Some actions can take Home Assistant offline or need physical access to recover, so the app blocks Claude from doing them on its own. This is on by default.

| Action | What happens |
|---|---|
| Stop Home Assistant | Blocked |
| Reboot or shut down the host | Blocked |
| Disable the Supervisor watchdog | Blocked |
| Update the operating system | Blocked |
| Restart Home Assistant | Asks you first |
| Restart the Supervisor | Asks you first |
| Lights, climate, scripts, reloads, editing files | Unaffected |

The reason is that an assistant can start a multi-step change and lose its place partway through. Stopping Home Assistant with the watchdog disabled leaves it down with nothing to bring it back. The guard makes that combination impossible rather than relying on Claude to remember.

It is a guardrail against mistakes, not a security sandbox. See [Settings](#settings) to adjust it, and issue [#29](https://github.com/sproft/hass-claude/issues/29) for the full design.

**When you actually want a blocked action to happen**, do it yourself in the Home Assistant UI, or turn the guard off with `guard_privileged_actions: false`. Adding one of the blocked actions to `confirm_actions` does not downgrade it, because the block list is built into the app and is checked first. See [Settings](#settings).

Claude is told to point you at those routes rather than hand you a command that works around the block, even if you ask it how. That is deliberate: the block exists so a privileged action gets a decision from you, and an assistant that volunteers the bypass in the same breath turns that decision back into a formality.

---

## Everyday use

### Starting and leaving Claude

| Type this | What it does |
|---|---|
| `c` | Start Claude |
| `cc` | Resume your previous conversation |
| `ha-config` | Jump to `/homeassistant` |
| `ha-logs` | Show the Home Assistant log |
| `ll` | Long directory listing |

To leave Claude, press `Ctrl-D` or type `/exit`. You land back at the shell prompt, and next time `cc` picks the conversation up where you left it.

**Your conversation is saved to disk either way, so closing the browser tab does not lose it.** `cc` brings it back regardless of how you left. What closing the tab does cost you is any work Claude was in the middle of, so if it is busy, press `Esc` and exit cleanly first.

(One exception: with `auto_continue` turned on there is no shell to land in, so exiting Claude closes the terminal session instead. Reopening it starts you straight back in the conversation.)

### One-off questions

You do not have to start an interactive session:

```bash
claude "list every unavailable entity"
```

### Your config folder is `/homeassistant`

Every Home Assistant guide you have read calls it `/config`. Inside this terminal it is **`/homeassistant`**. If you tell Claude "look at `/config/automations.yaml`" it knows to translate, but when you are typing paths yourself, use `/homeassistant`.

### Tools in the terminal

Besides Claude, the terminal has `git`, `gh`, `jq`, `ripgrep` (`rg`), `vim`, `nano`, `tmux`, the `ha` command line, `socat`, and `mbpoll` for Modbus. You can use it as a general-purpose config shell.

---

## Settings

Change these on the app's **Configuration** tab.

> **Every option takes effect when the app next starts.** Save your changes, then restart the app.

| Option | Default | What it does |
|---|---|---|
| `session_persistence` | `false` | Keep your session alive across browser refreshes and disconnects |
| `auto_continue` | `false` | Jump straight back into your last conversation on start. Needs `session_persistence: true` |
| `terminal_theme` | `dark` | Terminal colours, `dark` or `light` |
| `terminal_font_size` | `14` | Terminal font size in pixels, 10 to 24 |
| `auto_update_claude` | `false` | Download the newest Claude Code release in the background on every start |
| `claude_update_timeout` | `300` | Seconds that background update may take before it is stopped (30 to 1800) |
| `working_directory` | `/homeassistant` | Folder the terminal opens in |
| `enable_mcp` | `true` | Let Claude read entity states and call services, not just edit files |
| `guard_privileged_actions` | `true` | Enforce the safety guard described above |
| `disallow_actions` | six entries | Actions Claude may never run. Your entries **add** to a built-in baseline |
| `confirm_actions` | `homeassistant.restart`, `hassio.supervisor_restart` | Actions allowed only after you approve them |
| `unattended_mode` | `false` | Remove per-tool permission prompts entirely, for headless use. See below |

The `disallow_actions` baseline is `homeassistant.stop`, `supervisor.core_stop`, `supervisor.watchdog_disable`, `hassio.host_reboot`, `hassio.host_shutdown` and `hassio.os_update`. Removing one from the list does not re-enable it, because the baseline is built into the app. To allow a baseline action, turn the guard off.

`enable_mcp` behaves asymmetrically, which is worth knowing before you touch it. Turning it **on** also pre-approves Claude reading files in your config folder, so it stops asking about every file. Turning it back **off** undoes neither: the connection and the read pre-approvals stay in your settings until you remove them by hand. On a fresh install that has never run with it on, Claude has no entity access and asks before opening each file.

There is one more option, `working_directory`, which sets the folder the terminal opens in. It defaults to `/homeassistant` and most people never need to change it. If you point it somewhere that does not exist, the app logs a warning and opens in `/homeassistant` instead.

`unattended_mode` is for running Claude with nothing at the keyboard to answer prompts — a scheduled task, an automation-triggered session, anything where no human is watching the terminal. Turning it on sets `permissions.defaultMode: bypassPermissions` and exports `IS_SANDBOX=1`, which together are what let Claude Code run with zero per-tool prompts while this app is root inside its container. It does not touch the safety guard above: `guard_privileged_actions` keeps blocking and confirming the same actions either way, so leave that on. If you turn `unattended_mode` back off, the next app start removes the `bypassPermissions` setting again rather than leaving it in place — including if you (or an older version of this app) had set it by hand, so re-enable `unattended_mode` if that is how you got it there.

---

## Keeping your session alive

By default the terminal runs a plain shell. Close the tab and whatever was running stops.

Set `session_persistence: true` and the terminal runs inside tmux instead, so a browser refresh, a dropped connection or a closed tab all reattach to the same live conversation. Add `auto_continue: true` and the terminal comes straight back into your last conversation after a Home Assistant restart, with nothing to type.

The trade-off is copy and paste, which is why it is off by default:

| Action | Without tmux (default) | With tmux |
|---|---|---|
| Copy | Select with the mouse | Hold `Ctrl+Shift` while selecting |
| Paste | `Ctrl+V` | `Shift+Insert` or middle-click |
| Scroll | Normal browser scrolling | Mouse wheel, or `Ctrl+b` then `[` to scroll, `q` to exit |

Get signed in first, then turn it on. Pasting the login code is much easier without tmux.

Useful tmux keys: `Ctrl+b` then `d` detaches and leaves everything running.

Note that a tmux session survives a browser refresh but not an app or Home Assistant restart, since the app is rebuilt from scratch. That is what `auto_continue` is for.

---

## What Claude can reach

Worth reading once, so nothing here surprises you later.

| Folder | Purpose | Access |
|---|---|---|
| `/homeassistant` | Your Home Assistant configuration folder | Read and write |
| `/share` | Shared folder | Read and write |
| `/media` | Media folder | Read and write |
| `/config` | This app's own private settings folder, not your Home Assistant config | Read and write |
| `/ssl` | Certificates | Read only |
| `/backup` | Backups | Read only |

Beyond files, Claude can query any entity and call any service, and the app holds Supervisor-level access, which is how it reads logs and manages the system. The safety guard above is what keeps the destructive end of that away from it.

**Anyone who can sign in to your Home Assistant can open this terminal** and use it with all of the above. It is a shell on your system behind a sidebar icon. Treat installing it the way you would treat handing someone shell access, and think twice on an instance that is shared or exposed to the internet.

Your login and settings live in a hidden folder inside your configuration directory, `/homeassistant/.claudecode`. Two consequences: those credentials are included in your Home Assistant backups, and they survive reinstalling the app, so you do not have to sign in again.

---

## Updating Claude Code

Claude Code itself is a separate program from this app, and the two update independently.

A fresh install gets the version bundled with the app. **After that, updating the app does not replace it**, because your copy lives in the app's own persistent storage. So to get newer Claude Code releases you have to ask for them, either by turning on `auto_update_claude`, or by running this in the terminal whenever you like:

```bash
npm install -g @anthropic-ai/claude-code@latest
```

If you have a Claude session open, exit and restart it to pick up the new version.

On machines with little RAM, leave `auto_update_claude` off and update by hand now and then. That download is the most common cause of the app being killed while it starts.

---

## Troubleshooting

### I cannot paste the login code, or I get a "400" error

The code is long and easy to break.

- The URL wrapped across lines and you copied part of it. Zoom out (`Ctrl` and `-`) until it fits on one line, then click it.
- The code expired. Run `c` again for a fresh one.
- If you turned on `session_persistence`, tmux intercepts pasting. Use `Shift+Insert` or middle-click, not `Ctrl+V`.

### The app is killed while starting, or `claude` prints only "Killed"

Usually memory, on smaller VMs.

1. Give the machine more RAM. 2 GB or more is the practical floor.
2. Set `auto_update_claude: false` so npm does not run on every start.
3. Set `session_persistence: false` to trim a little more.

If you are on Proxmox and it still happens instantly, check the log with `dmesg | tail -30`. If the CPU type is `kvm64`, change it to `host`, because the CLI needs instructions that `kvm64` does not expose.

### Claude cannot see my entities or call services

1. Check `enable_mcp` is `true` on the Configuration tab.
2. Restart the app after changing it.
3. Look at the app's **Log** tab for connection errors.

### The terminal keeps reconnecting, or Claude exits immediately

Fixed in 1.2.79. Update the app and restart it, and the app repairs the setting that caused it on the next start.

If you are stuck on an older version, turn `auto_update_claude` **off** first. With it on, the app updates, crashes, gets restarted by the watchdog, and repeats.

### A change on the Configuration tab did nothing

Options are read when the app starts. Save, then restart the app.

If it was `auto_continue`, check `session_persistence` is also `true`. It does nothing on its own.

### Claude changed something and now Home Assistant will not start

1. Check the Home Assistant log for the YAML error, which usually names the file and line.
2. Ask Claude to fix it, or revert the file yourself.
3. If you cannot get back in, restore the backup you took before the change.

### The guard refused something I actually wanted

By design. Do it yourself in the Home Assistant UI, or set `guard_privileged_actions: false` to turn the guard off entirely.

Moving one of the six built-in blocks into `confirm_actions` will **not** turn it into a prompt. The built-in list is checked first and wins, so the action stays refused. Downgrading only works for actions you added to `disallow_actions` yourself.

Also note that if you run Claude in one-off mode (`claude "..."`) there is nobody to answer a confirmation prompt, so anything on the confirm list is skipped rather than run.

### `claude: command not found`, or a permission error

Update to the latest version first, since several older releases had this. If it survives the update, uninstall and reinstall the app: Home Assistant does not always reload an app's security profile on an in-place update.

### The terminal does not load

1. Confirm the app is running.
2. Reload the page.
3. Check the app's **Log** tab.

---

## Support

- [GitHub Issues](https://github.com/sproft/hass-claude/issues)
- [Changelog](CHANGELOG.md)
- [Home Assistant Community](https://community.home-assistant.io/)
