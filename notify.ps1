param([string]$Message = "")

# ── Hook entry point: ensure daemon alive, debounce, play sound, write trigger, exit fast ──

# Auto-start daemon if not running
$daemonLock = "$env:TEMP\claude_notify_daemon.lock"
$daemonAlive = $false
if (Test-Path $daemonLock) {
    try {
        $daemonPid = [int](Get-Content $daemonLock -Raw).Trim()
        $daemonProc = Get-Process -Id $daemonPid -ErrorAction SilentlyContinue
        if ($daemonProc -and $daemonProc.ProcessName -eq "powershell") { $daemonAlive = $true }
    } catch {}
}
if (-not $daemonAlive) {
    $daemonPath = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "notify-daemon.ps1"
    Start-Process powershell -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", $daemonPath)
}

$lockFile = "$env:TEMP\claude_notify_lock.txt"
$now = Get-Date
if (Test-Path $lockFile) {
    $last = Get-Date (Get-Content $lockFile)
    if (($now - $last).TotalSeconds -lt 90) { exit 0 }
}
$now.ToString("o") | Out-File $lockFile -Force

# Instant audio — plays before WPF even loads
[System.Media.SystemSounds]::Asterisk.Play()

# Try stdin for hook JSON (dynamic task summary)
if ([string]::IsNullOrEmpty($Message)) {
    try {
        $stdinLines = @()
        while ($null -ne ($line = [Console]::In.ReadLine())) { $stdinLines += $line }
        $stdin = $stdinLines -join "`n"
        if ($stdin) {
            $json = $stdin | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($json -and $json.user_prompt) {
                $prompt = $json.user_prompt
                if ($prompt.Length -gt 40) { $prompt = $prompt.Substring(0, 37) + "..." }
                $Message = "Finished: `"$prompt`""
            }
        }
    } catch {}
}
if ([string]::IsNullOrEmpty($Message)) { $Message = "Task completed" }

# Write trigger file — daemon picks it up within 250ms
$triggerFile = "$env:TEMP\claude_notify_trigger.txt"
$Message | Out-File -FilePath $triggerFile -Encoding utf8 -Force
