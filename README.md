# ClaudeCodeNotifyBeacon

A premium Dynamic Island-style desktop notification pill for [Claude Code](https://claude.ai/code). Built with WPF for hardware-accelerated rendering, featuring the official Claude brand icon with correct SVG rendering and Windows 11 native rounded corners.

![ClaudeCodeNotifyBeacon](assets/screenshot.png)

## Features

- **Dynamic Island pill** — 400×92 custom WPF floating window, CornerRadius 26, drop shadow
- **Zero-latency daemon** — WPF assemblies pre-loaded in a persistent background process; pill appears within 250ms of task completion
- **Official Claude SVG icon** — SVG-parsed brand logo with correct EvenOdd fill-rule via `GeometryDrawing`
- **Windows 11 native rounded corners** — DWM API (`DWMWCP_ROUNDSMALL`) for true rounded window edges
- **GPU-accelerated Storyboards** — entrance (300ms scale+fade), auto-dismiss (250ms fade after 8s), click dismiss (120ms fade)
- **Dynamic task context** — reads hook stdin JSON to show real task summaries in the pill body
- **Debounce** — 90s lock file prevents duplicate notifications

## Why ClaudeCodeNotifyBeacon?

Most Claude Code notification projects for Windows use `[Windows.UI.Notifications]` toast messages — the standard system popup in the bottom-right corner. ClaudeCodeNotifyBeacon takes a different approach:

| Feature | ClaudeCodeNotifyBeacon | Toast-based notifiers |
|---|---|---|
| **Rendering** | Custom WPF floating window | System toast API |
| **Design** | Dynamic Island pill with brand icon | Standard Windows notification |
| **Icon** | Official Claude SVG (EvenOdd fill) | N/A or raster fallback |
| **Rounded corners** | DWM native (Win32 level) | System-determined |
| **Latency** | ~250ms (pre-warmed daemon) | Varies (PowerShell cold start) |
| **Dismiss** | Click 120ms fade + 8s auto-fade | System-managed |
| **GPU accelerated** | Yes (WPF Storyboard) | No |
| **Architecture** | Daemon + trigger file | Direct PowerShell call |

ClaudeCodeNotifyBeacon is the only project that renders a custom floating WPF pill with the official Claude brand SVG using correct EvenOdd geometry — because a premium AI tool deserves a premium notification.

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (built-in)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

## Quick Start

### 1. Clone or download

```powershell
git clone https://github.com/Junyi-Tang/ClaudeCodeNotifyBeacon.git
# or just download notify.ps1, notify-daemon.ps1, and assets/
```

### 2. Install (recommended)

Run the installer from the project folder. It registers the hooks in your
`~/.claude/settings.json` (backing up any existing file first, never duplicating
entries) and starts the daemon:

```powershell
.\install.ps1
```

Restart any open Claude Code session afterward so it reloads `settings.json`.

> **Note:** the installer registers a **`Stop`** hook (fires every time Claude
> finishes a turn — this is the reliable trigger) and a **`Notification`** hook
> (fires when Claude Code emits its own notification). The `Stop` hook works
> regardless of your `preferredNotifChannel` setting.

### Or configure manually

Add to your Claude Code settings (`~/.claude/settings.json` or project `.claude/settings.json`):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File \"C:\\Users\\YOURNAME\\path\\to\\ClaudeCodeNotifyBeacon\\notify.ps1\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File \"C:\\Users\\YOURNAME\\path\\to\\ClaudeCodeNotifyBeacon\\notify.ps1\" -Message \"Session complete\""
          }
        ]
      }
    ]
  }
}
```

> **About `preferredNotifChannel`:** setting it to `"notifications_disabled"`
> stops Claude Code from sending its *own* OS notification, which avoids a
> double-notify alongside the pill — but it can also suppress the
> **`Notification`** hook. The **`Stop`** hook fires either way, so leave this
> setting at its default unless you specifically want to silence Claude's
> native notifications and rely on the `Stop` hook alone.

### 3. Start the daemon (manual install only)

```powershell
Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-STA",
    "-File", """C:\Users\YOURNAME\path\to\ClaudeCodeNotifyBeacon\notify-daemon.ps1"""
)
```

The daemon stays running in the background. Start it once per login session.

### 4. Test

```powershell
"Test notification" | Out-File -FilePath "$env:TEMP\claude_notify_trigger.txt" -Encoding utf8 -Force
```

## How It Works

```
┌─────────────┐     ┌──────────────┐     ┌──────────────────┐
│ Claude Code │ ──▶ │  notify.ps1   │ ──▶ │ notify-daemon.ps1│
│ Notification│     │ write trigger │     │ WPF pill on      │
│ or Stop hook│     │ file + exit   │     │ screen ~8s       │
└─────────────┘     └──────────────┘     └──────────────────┘
                           ~10ms               ~250ms poll
```

1. Claude Code finishes a task → `Notification` hook fires (shows task summary); or the agentic loop ends → `Stop` hook fires (shows "Session complete")
2. `notify.ps1` runs: debounce check → writes trigger file → exits
3. `notify-daemon.ps1` (persistent background process with WPF pre-loaded) detects the trigger within 250ms → renders the Dynamic Island pill instantly

The 90-second debounce means only one pill appears if both hooks fire for the same event.

## File Structure

```
ClaudeCodeNotifyBeacon/
├── install.ps1              # One-command installer (registers hooks + starts daemon)
├── notify.ps1               # Hook entry point (trigger writer)
├── notify-daemon.ps1        # Persistent notification daemon (WPF)
├── assets/
│   └── claudecode-color.svg # Official Claude Code brand icon
└── README.md
```

## License

MIT
