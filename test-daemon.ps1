# Simple test to see if daemon can show a notification
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

Write-Host "Loading WPF..."

$triggerFile = "$env:TEMP\claude_notify_trigger.txt"

if (Test-Path $triggerFile) {
    $Message = (Get-Content $triggerFile -Encoding utf8 -Raw).Trim()
    Write-Host "Found trigger: $Message"

    try {
        $window = New-Object System.Windows.Window
        $window.WindowStyle = 'None'
        $window.AllowsTransparency = $true
        $window.Background = [System.Windows.Media.Brushes]::Black
        $window.Topmost = $true
        $window.ShowInTaskbar = $false
        $window.Width = 400
        $window.Height = 90
        $window.Left = 100
        $window.Top = 100

        $text = New-Object System.Windows.Controls.TextBlock
        $text.Text = $Message
        $text.Foreground = [System.Windows.Media.Brushes]::White
        $text.FontSize = 16
        $text.Margin = New-Object System.Windows.Thickness(20)

        $window.Content = $text

        Write-Host "Showing window..."
        $window.Show()

        Start-Sleep -Seconds 3
        $window.Close()
        Write-Host "Window closed"
    } catch {
        Write-Host "ERROR: $_"
        Write-Host $_.ScriptStackTrace
    }
} else {
    Write-Host "No trigger file found at $triggerFile"
}
