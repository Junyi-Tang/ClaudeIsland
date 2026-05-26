# Claude Code Notification Beacon

WPF desktop notification daemon for Claude Code task completion events. Shows a Fluent Dark pill notification at bottom-right when a Claude Code task finishes.

## Architecture

```
Claude Code hook
  → notify.ps1          # Entry point: auto-starts daemon, plays sound, writes trigger
    → notify-daemon.ps1 # Persistent daemon: watches trigger file, shows WPF notification
```

## Files

| File | Role |
|---|---|
| `notify.ps1` | Hook entry point. Checks daemon liveness via PID lock, auto-starts if dead, debounces (90s cooldown), reads stdin for hook JSON, writes trigger file. Polls ready-signal file after starting daemon to prevent startup race. |
| `notify-daemon.ps1` | Long-running WPF daemon. Uses `DispatcherTimer` (250ms interval) integrated with the WPF message pump to detect trigger files with near-zero latency. Plays `Asterisk` chime on notification. Single-instance via PID lock file. Signals ready via `claude_notify_ready.txt`. |
| `assets/claudecode-color.svg` | Claude Code wordmark icon rendered in the notification badge. |

## Trigger protocol

All files live in `$env:TEMP`:

| File | Purpose |
|---|---|
| `claude_notify_trigger.txt` | Message payload. Daemon reads and displays content, then deletes it. |
| `claude_notify_daemon.lock` | Contains daemon PID. Used for single-instance guard and liveness check. |
| `claude_notify_ready.txt` | Written by daemon once `WaitForChanged` is primed. `notify.ps1` polls this before writing trigger. |
| `claude_notify_lock.txt` | Debounce timestamp. `notify.ps1` skips if last trigger was < 90s ago. |

## Daemon startup

```powershell
Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-STA",
    "-File", "path\to\notify-daemon.ps1"
)
```

`-STA` is required — WPF objects must be created on an STA thread.

## Known issues

- **Double sound (resolved):** Sound plays once in `notify-daemon.ps1` after `$window.Show()`. `notify.ps1` does not play sound, so no overlap.

## Changelog

- **2026-05-25:** Replaced `FileSystemWatcher.WaitForChanged` (commit `04b6bd2`) with `DispatcherTimer`-based polling (250ms interval). `WaitForChanged` blocked the STA thread in a way that prevented WPF's dispatcher from properly pumping messages, so `PushFrame` inside `Show-Notification` never rendered the window. `DispatcherTimer` integrates directly with the WPF message pump — the timer ticks on the UI thread, and `PushFrame` in Show-Notification creates a proper nested message loop for animations.

## Design

- **Theme:** Fluent Dark — `rgb(20, 20, 22)` card, 1px subliminal white border at 15% opacity, 26px corner radius
- **Icon:** Claude Code wordmark in warm orange gradient (`#F37658` → `#D93535`)
- **Typography:** Segoe UI, SemiBold title (14.5px), slate body (12.5px)
- **Animation:** CubicEase entrance (300ms scale 0.92→1.0 + fade), 8s auto-dismiss
- **Hover:** Timestamp crossfades to "Click to dismiss" via Opacity swap (no layout shift)
- **Shadow:** `DropShadowEffect` BlurRadius 35, Opacity 0.28
- **Window:** 400×92px, bottom-right corner, `WindowChrome` strips Win32 border artifacts
