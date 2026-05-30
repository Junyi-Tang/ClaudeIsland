#requires -Version 5.1
# ── ClaudeCodeNotifyBeacon installer ──
# Registers the notification hooks into your Claude Code settings.json and starts
# the daemon. Safe to re-run: it backs up settings.json and never duplicates an
# entry that already points at this notify.ps1.
#
#   .\install.ps1            # register hooks + start daemon
#   .\install.ps1 -NoDaemon  # register hooks only

param([switch]$NoDaemon)

$ErrorActionPreference = 'Stop'

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$notifyPath = Join-Path $scriptDir 'notify.ps1'
$daemonPath = Join-Path $scriptDir 'notify-daemon.ps1'

foreach ($p in @($notifyPath, $daemonPath)) {
    if (-not (Test-Path $p)) { throw "Required file not found next to install.ps1: $p" }
}

$settingsDir  = Join-Path $env:USERPROFILE '.claude'
$settingsPath = Join-Path $settingsDir 'settings.json'
if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null }

# ── Load existing settings (validate JSON, keep all unrelated keys) ──
$settings = [ordered]@{}
if (Test-Path $settingsPath) {
    $raw = Get-Content $settingsPath -Raw
    if ($raw -and $raw.Trim()) {
        try { $parsed = $raw | ConvertFrom-Json } catch { throw "settings.json is not valid JSON: $settingsPath" }
        foreach ($prop in $parsed.PSObject.Properties) { $settings[$prop.Name] = $prop.Value }
    }
    Copy-Item $settingsPath "$settingsPath.bak" -Force
    Write-Host "Backed up existing settings -> $settingsPath.bak"
}

# ── Hook command strings (absolute path so they work from any cwd) ──
$notifyCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $notifyPath
$stopCmd   = '{0} -Message "Session complete"' -f $notifyCmd

# ── Ensure a hooks container exists ──
if (-not $settings.Contains('hooks') -or -not $settings['hooks']) {
    $settings['hooks'] = [PSCustomObject]@{}
}
$hooks = $settings['hooks']

function Add-HookEntry {
    param($HooksObj, [string]$EventName, $Entry, [string]$Marker)
    $existing = @()
    $prop = $HooksObj.PSObject.Properties[$EventName]
    if ($prop -and $prop.Value) { $existing = @($prop.Value) }
    foreach ($e in $existing) {
        foreach ($h in @($e.hooks)) {
            if ($h.command -and $h.command -like "*$Marker*") {
                Write-Host "  $EventName hook already registered - skipping."
                return
            }
        }
    }
    $existing += $Entry
    if ($prop) { $prop.Value = $existing }
    else { $HooksObj | Add-Member -NotePropertyName $EventName -NotePropertyValue $existing -Force }
    Write-Host "  Added $EventName hook."
}

$notificationEntry = [PSCustomObject]@{
    matcher = ''
    hooks   = @([PSCustomObject]@{ type = 'command'; command = $notifyCmd })
}
$stopEntry = [PSCustomObject]@{
    hooks   = @([PSCustomObject]@{ type = 'command'; command = $stopCmd })
}

# Detect prior installs by matching the notify.ps1 reference in a hook command
$marker = 'notify.ps1'
Add-HookEntry -HooksObj $hooks -EventName 'Stop'         -Entry $stopEntry         -Marker $marker
Add-HookEntry -HooksObj $hooks -EventName 'Notification' -Entry $notificationEntry -Marker $marker
$settings['hooks'] = $hooks

# ── Write back ──
($settings | ConvertTo-Json -Depth 12) | Set-Content -Path $settingsPath -Encoding UTF8
Write-Host "Wrote hooks to $settingsPath"

# ── Start the daemon ──
if (-not $NoDaemon) {
    Start-Process powershell -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $daemonPath)
    Write-Host "Started notification daemon."
}

Write-Host ""
Write-Host "Done. A pill fires when Claude Code finishes a turn (Stop hook) or"
Write-Host "sends a notification (Notification hook). Restart any open Claude Code"
Write-Host "session so it reloads settings.json."
