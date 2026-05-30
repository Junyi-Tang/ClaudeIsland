# Claude Code Notification Beacon

WPF desktop notification daemon for Claude Code task completion events. Shows a Fluent Dark pill notification at bottom-right when a Claude Code task finishes.

## Architecture

```
Claude Code hook
  → notify.ps1          # Entry point: auto-starts daemon, writes trigger
    → notify-daemon.ps1 # Persistent daemon: watches trigger file, shows WPF notification
```

## Files

| File | Role |
|---|---|
| `notify.ps1` | Hook entry point. Checks daemon liveness via PID lock (verifies CommandLine contains `notify-daemon.ps1` to prevent PID-collision false positives), auto-starts if dead, debounces (90s cooldown), reads stdin for hook JSON, writes trigger via atomic `WriteAllText`. Polls ready-signal file after starting daemon to prevent startup race. |
| `notify-daemon.ps1` | Long-running WPF daemon. Uses `DispatcherTimer` at 50ms (imperceptible latency, well below the ~100ms human perception threshold). Single-instance via PID lock (same CommandLine guard). Signals ready via `claude_notify_ready.txt`. Plays `Asterisk` chime on notification. |
| `assets/claudecode-color.svg` | Claude Code wordmark icon rendered in the notification badge. |

## Trigger protocol

All files live in `$env:TEMP`:

| File | Purpose |
|---|---|
| `claude_notify_trigger.txt` | Message payload. Daemon reads and displays content, then deletes it. |
| `claude_notify_daemon.lock` | Contains daemon PID. Used for single-instance guard and liveness check. |
| `claude_notify_ready.txt` | Written by daemon once the DispatcherTimer is primed. `notify.ps1` polls this before writing trigger. Deleted by `notify.ps1` before each daemon launch to prevent stale-file false positives. |
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

- **Double sound (resolved):** Sound plays once in `notify-daemon.ps1` after `$window.Show()`. `notify.ps1` never plays sound.

## Changelog

- **2026-05-25 (v3):** Reduced `DispatcherTimer` interval from 250ms to 50ms. At 50ms the polling latency is well below the ~100ms human perception threshold, making notifications feel instant. Attempted `FileSystemWatcher` event-based approaches (`.add_Changed`, `Register-ObjectEvent`) — both failed due to PowerShell threading/scope limitations (no runspace on thread pool threads; module scope isolation in event actions). Pure `DispatcherTimer` at 50ms is the reliable sweet spot.
- **2026-05-25 (v2):** Replaced `FileSystemWatcher.WaitForChanged` with `DispatcherTimer`-based polling (250ms interval). `WaitForChanged` blocked the STA thread and prevented WPF's `PushFrame` from rendering the window.
- **2026-05-25 (v1):** Initial version.

## Design

- **Theme:** Fluent Dark — `rgb(20, 20, 22)` card, 1px subliminal white border at 15% opacity, 26px corner radius
- **Icon:** Claude Code wordmark in warm orange gradient (`#F37658` → `#D93535`)
- **Typography:** Segoe UI, SemiBold title (14.5px), slate body (12.5px)
- **Animation:** CubicEase entrance (300ms scale 0.92→1.0 + fade), 8s auto-dismiss
- **Hover:** Timestamp crossfades to "Click to dismiss" via Opacity swap (no layout shift)
- **Shadow:** `DropShadowEffect` BlurRadius 35, Opacity 0.28
- **Window:** 400×92px, bottom-right corner, `WindowChrome` strips Win32 border artifacts
