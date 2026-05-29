param([string]$Message = "")

# ── Hook entry point: ensure daemon alive, debounce, play sound, write trigger, exit fast ──

# Auto-start daemon if not running
$daemonLock = "$env:TEMP\claude_notify_daemon.lock"
$daemonAlive = $false
if (Test-Path $daemonLock) {
    try {
        $daemonPid = [int](Get-Content $daemonLock -Raw).Trim()
        $daemonProc = Get-Process -Id $daemonPid -ErrorAction SilentlyContinue
        if ($daemonProc -and $daemonProc.ProcessName -eq "powershell") {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$daemonPid" -ErrorAction SilentlyContinue).CommandLine
            if ($cmdLine -like "*notify-daemon.ps1*") { $daemonAlive = $true }
        }
    } catch {}
}
if (-not $daemonAlive) {
    $daemonPath = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "notify-daemon.ps1"
    Remove-Item "$env:TEMP\claude_notify_ready.txt" -Force -ErrorAction SilentlyContinue
    Start-Process powershell -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", $daemonPath)
    # Wait for daemon to signal ready (up to 10s)
    $readyFile = "$env:TEMP\claude_notify_ready.txt"
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        if (Test-Path $readyFile) { break }
    }
}

$lockFile = "$env:TEMP\claude_notify_lock.txt"
$now = Get-Date
if (Test-Path $lockFile) {
    $last = Get-Date (Get-Content $lockFile)
    if (($now - $last).TotalSeconds -lt 90) { exit 0 }
}
$now.ToString("o") | Out-File $lockFile -Force

# Hook stdin parsing (non-blocking)
if ([string]::IsNullOrEmpty($Message)) {
    try {
        if ([Console]::In.Peek() -ne -1) {
            $stdinLines = @()
            while ([Console]::In.Peek() -ne -1 -and ($null -ne ($line = [Console]::In.ReadLine()))) { $stdinLines += $line }
            $stdin = $stdinLines -join "`n"
            if ($stdin) {
                $json = $stdin | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($json -and $json.user_prompt) {
                    $prompt = $json.user_prompt
                    if ($prompt.Length -gt 40) { $prompt = $prompt.Substring(0, 37) + "..." }
                    $Message = "Finished: `"$prompt`""
                }
            }
        }
    } catch {}
}
if ([string]::IsNullOrEmpty($Message)) { $Message = "Task completed" }

# Write trigger — atomic write so FileSystemWatcher fires on complete content
$triggerFile = "$env:TEMP\claude_notify_trigger.txt"
[System.IO.File]::WriteAllText($triggerFile, $Message, [System.Text.Encoding]::UTF8)
