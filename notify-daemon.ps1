# ── Notification daemon — watches trigger file, shows WPF pill instantly ──
# Start once per session: Start-Process powershell -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", """<path-to>\notify-daemon.ps1""")

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

$triggerFile = "$env:TEMP\claude_notify_trigger.txt"
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$assetDir = Join-Path $scriptDir "assets"
if (-not (Test-Path $assetDir)) { New-Item -ItemType Directory -Path $assetDir -Force | Out-Null }
$svgPath = Join-Path $assetDir "claudecode-color.svg"

# Pre-warm SVG path data
$svgPathDataCached = $null
if (Test-Path $svgPath) {
    try {
        $svgXml = [xml](Get-Content $svgPath -Encoding UTF8)
        $ns = New-Object Xml.XmlNamespaceManager $svgXml.NameTable
        $ns.AddNamespace("sv", "http://www.w3.org/2000/svg")
        $pathNode = $svgXml.SelectSingleNode("//sv:path[@d]", $ns)
        if ($pathNode) { $svgPathDataCached = $pathNode.GetAttribute("d") }
    } catch {}
}
if (-not $svgPathDataCached) {
    $svgPathDataCached = "M13 3.5c-4.7 0-8.5 3.8-8.5 8.5s3.8 8.5 8.5 8.5c3.2 0 6-1.8 7.4-4.5M11.5 8.5c-2.2 0-4 1.8-4 4s1.8 4 4 4c1.5 0 2.8-.8 3.5-2"
}

# Pre-warm theme tokens (Fluent Dark Theme Palette)
$cardBg       = [System.Windows.Media.Color]::FromRgb(20, 20, 22)
$borderColor  = [System.Windows.Media.Color]::FromArgb(40, 255, 255, 255) # Subliminal border
$white        = [System.Windows.Media.Color]::FromRgb(245, 245, 247)
$slate        = [System.Windows.Media.Color]::FromRgb(155, 160, 170)
$hintColor    = [System.Windows.Media.Color]::FromRgb(100, 102, 110)

$accentBrush = New-Object System.Windows.Media.LinearGradientBrush
$accentBrush.StartPoint = New-Object System.Windows.Point(0, 0)
$accentBrush.EndPoint = New-Object System.Windows.Point(1, 1)
$a1 = New-Object System.Windows.Media.GradientStop([System.Windows.Media.Color]::FromRgb(243, 118, 88), 0.0)
$a2 = New-Object System.Windows.Media.GradientStop([System.Windows.Media.Color]::FromRgb(217, 83, 53), 1.0)
$accentBrush.GradientStops.Add($a1) | Out-Null
$accentBrush.GradientStops.Add($a2) | Out-Null

$iconBgBrush = New-Object System.Windows.Media.SolidColorBrush(
    [System.Windows.Media.Color]::FromArgb(18, 255, 255, 255)
)

$propOpacity = New-Object System.Windows.PropertyPath("Opacity")
$propScaleX  = New-Object System.Windows.PropertyPath("ScaleX")
$propScaleY  = New-Object System.Windows.PropertyPath("ScaleY")

# Single-instance guard — write PID so notify.ps1 can detect us
$daemonLock = "$env:TEMP\claude_notify_daemon.lock"
if (Test-Path $daemonLock) {
    try {
        $existingPid = [int](Get-Content $daemonLock -Raw).Trim()
        $existingProc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
        if ($existingProc -and $existingProc.ProcessName -eq "powershell") { exit 0 }
    } catch {}
}
$PID | Out-File -FilePath $daemonLock -Force

# ── FileSystemWatcher — native FS events, instant with zero CPU ──
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $env:TEMP
$watcher.Filter = "claude_notify_trigger.txt"
$watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName
$watcher.IncludeSubdirectories = $false
$changeTypes = [System.IO.WatcherChangeTypes]::Changed -bor [System.IO.WatcherChangeTypes]::Created

# Signal that daemon is ready to receive events
$readyFile = "$env:TEMP\claude_notify_ready.txt"
"$PID" | Out-File -FilePath $readyFile -Force

# Debounce state — prevent duplicate events and double-sound
$script:lastEventTime = [DateTime]::MinValue
$debounceMs = 100

function Show-Notification {
    param([string]$Message)

    $showTime = Get-Date
    $screen = [System.Windows.SystemParameters]::WorkArea

    # ── Window (Fully Stripped Chrome) ──
    $window = New-Object System.Windows.Window
    $window.WindowStyle = 'None'
    $window.AllowsTransparency = $true
    $window.Background = [System.Windows.Media.Brushes]::Transparent
    $window.Topmost = $true
    $window.ShowInTaskbar = $false
    $window.ShowActivated = $false
    $window.ResizeMode = 'NoResize'

    $chrome = New-Object System.Windows.Shell.WindowChrome
    $chrome.CaptionHeight = 0
    $chrome.CornerRadius = New-Object System.Windows.CornerRadius(0)
    $chrome.GlassFrameThickness = New-Object System.Windows.Thickness(0)
    $chrome.ResizeBorderThickness = New-Object System.Windows.Thickness(0)
    [System.Windows.Shell.WindowChrome]::SetWindowChrome($window, $chrome)

    $window.Width = 400
    $window.Height = 92
    $window.Left = $screen.Width - $window.Width - 16
    $window.Top = $screen.Height - $window.Height - 16

    # ── Card Container ──
    $card = New-Object System.Windows.Controls.Border
    $card.CornerRadius = New-Object System.Windows.CornerRadius(26)
    $card.Background = New-Object System.Windows.Media.SolidColorBrush($cardBg)
    $card.BorderBrush = New-Object System.Windows.Media.SolidColorBrush($borderColor)
    $card.BorderThickness = New-Object System.Windows.Thickness(1)
    $card.Padding = New-Object System.Windows.Thickness(20, 0, 20, 0)
    $card.Cursor = [System.Windows.Input.Cursors]::Hand

    $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
    $shadow.BlurRadius = 35; $shadow.Opacity = 0.28; $shadow.ShadowDepth = 5; $shadow.Direction = 270
    $card.Effect = $shadow

    # ── Grid Layout ──
    $innerGrid = New-Object System.Windows.Controls.Grid
    $iconCol = New-Object System.Windows.Controls.ColumnDefinition
    $iconCol.Width = [System.Windows.GridLength]::new(48)
    $textCol = New-Object System.Windows.Controls.ColumnDefinition
    $textCol.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $badgeCol = New-Object System.Windows.Controls.ColumnDefinition
    $badgeCol.Width = [System.Windows.GridLength]::Auto
    $innerGrid.ColumnDefinitions.Add($iconCol) | Out-Null
    $innerGrid.ColumnDefinitions.Add($textCol) | Out-Null
    $innerGrid.ColumnDefinitions.Add($badgeCol) | Out-Null

    # ── Icon Badge ──
    $iconBadge = New-Object System.Windows.Controls.Border
    $iconBadge.Width = 38; $iconBadge.Height = 38
    $iconBadge.CornerRadius = New-Object System.Windows.CornerRadius(12)
    $iconBadge.Background = $iconBgBrush
    $iconBadge.VerticalAlignment = 'Center'
    $iconBadge.HorizontalAlignment = 'Left'
    [System.Windows.Controls.Grid]::SetColumn($iconBadge, 0)

    $svgGeo = [System.Windows.Media.Geometry]::Parse($svgPathDataCached)
    $pathGeo = New-Object System.Windows.Media.PathGeometry
    $pathGeo.AddGeometry($svgGeo)
    $pathGeo.FillRule = 'EvenOdd'
    $geoDrw = New-Object System.Windows.Media.GeometryDrawing
    $geoDrw.Brush = $accentBrush; $geoDrw.Geometry = $pathGeo
    $drwImg = New-Object System.Windows.Media.DrawingImage($geoDrw)

    $iconImage = New-Object System.Windows.Controls.Image
    $iconImage.Source = $drwImg
    $iconImage.Stretch = 'Uniform'
    $iconImage.VerticalAlignment = 'Center'
    $iconImage.HorizontalAlignment = 'Center'
    $iconImage.Width = 22; $iconImage.Height = 22
    $iconBadge.Child = $iconImage
    $innerGrid.Children.Add($iconBadge) | Out-Null

    # ── Text Layout Stack ──
    $textStack = New-Object System.Windows.Controls.StackPanel
    $textStack.VerticalAlignment = 'Center'
    $textStack.Margin = New-Object System.Windows.Thickness(12, 0, 8, 0)
    [System.Windows.Controls.Grid]::SetColumn($textStack, 1)

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Claude Code"
    $title.Foreground = New-Object System.Windows.Media.SolidColorBrush($white)
    $title.FontFamily = "Segoe UI"
    $title.FontWeight = 'SemiBold'
    $title.FontSize = 14.5

    $body = New-Object System.Windows.Controls.TextBlock
    $body.Text = $Message
    $body.Foreground = New-Object System.Windows.Media.SolidColorBrush($slate)
    $body.FontFamily = "Segoe UI"
    $body.FontSize = 12.5
    $body.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
    $body.TextWrapping = 'NoWrap'
    $body.TextTrimming = 'CharacterEllipsis'

    $textStack.Children.Add($title) | Out-Null
    $textStack.Children.Add($body) | Out-Null
    $innerGrid.Children.Add($textStack) | Out-Null

    # ── Right Side Meta (Timestamp + Hint Overlay) ──
    $metaGrid = New-Object System.Windows.Controls.Grid
    $metaGrid.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($metaGrid, 2)

    $statusBadge = New-Object System.Windows.Controls.TextBlock
    $statusBadge.Text = $showTime.ToString("HH:mm")
    $statusBadge.Foreground = New-Object System.Windows.Media.SolidColorBrush($hintColor)
    $statusBadge.FontFamily = "Segoe UI"
    $statusBadge.FontSize = 11
    $statusBadge.VerticalAlignment = 'Center'
    $statusBadge.Margin = New-Object System.Windows.Thickness(4, 0, 2, 0)
    $statusBadge.Opacity = 1.0

    $hint = New-Object System.Windows.Controls.TextBlock
    $hint.Text = "Click to dismiss"
    $hint.Foreground = New-Object System.Windows.Media.SolidColorBrush($hintColor)
    $hint.FontFamily = "Segoe UI"
    $hint.FontSize = 10.5
    $hint.VerticalAlignment = 'Center'
    $hint.Margin = New-Object System.Windows.Thickness(4, 0, 2, 0)
    $hint.Opacity = 0.0

    $metaGrid.Children.Add($statusBadge) | Out-Null
    $metaGrid.Children.Add($hint) | Out-Null
    $innerGrid.Children.Add($metaGrid) | Out-Null

    $card.Child = $innerGrid
    $window.Content = $card

    # ── Micro Interaction (Hover Effects) ──
    $card.Add_MouseEnter({
        $statusBadge.Opacity = 0.0
        $hint.Opacity = 1.0
    })
    $card.Add_MouseLeave({
        $hint.Opacity = 0.0
        $statusBadge.Opacity = 1.0
    })

    # ── Entrance Animation ──
    $scaleTransform = New-Object System.Windows.Media.ScaleTransform(0.92, 0.92)
    $card.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
    $card.RenderTransform = $scaleTransform
    $window.Opacity = 0

    $enterSB = New-Object System.Windows.Media.Animation.Storyboard
    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = 'EaseOut'

    $eo = New-Object System.Windows.Media.Animation.DoubleAnimation
    $eo.From = 0; $eo.To = 1.0; $eo.Duration = [System.TimeSpan]::FromMilliseconds(300)
    $eo.EasingFunction = $ease
    [System.Windows.Media.Animation.Storyboard]::SetTarget($eo, $window)
    [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($eo, $propOpacity)
    $enterSB.Children.Add($eo) | Out-Null

    $esx = New-Object System.Windows.Media.Animation.DoubleAnimation
    $esx.From = 0.92; $esx.To = 1.0; $esx.Duration = [System.TimeSpan]::FromMilliseconds(300)
    $esx.EasingFunction = $ease
    [System.Windows.Media.Animation.Storyboard]::SetTarget($esx, $scaleTransform)
    [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($esx, $propScaleX)
    $enterSB.Children.Add($esx) | Out-Null

    $esy = New-Object System.Windows.Media.Animation.DoubleAnimation
    $esy.From = 0.92; $esy.To = 1.0; $esy.Duration = [System.TimeSpan]::FromMilliseconds(300)
    $esy.EasingFunction = $ease
    [System.Windows.Media.Animation.Storyboard]::SetTarget($esy, $scaleTransform)
    [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($esy, $propScaleY)
    $enterSB.Children.Add($esy) | Out-Null

    # ── Lifecycle Loop ──
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $script:closing = $false

    $exitSB = New-Object System.Windows.Media.Animation.Storyboard
    $ef = New-Object System.Windows.Media.Animation.DoubleAnimation
    $ef.From = 1.0; $ef.To = 0.0
    $ef.Duration = [System.TimeSpan]::FromMilliseconds(250)
    $ef.BeginTime = [System.TimeSpan]::FromSeconds(8)
    [System.Windows.Media.Animation.Storyboard]::SetTarget($ef, $window)
    [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($ef, $propOpacity)
    $exitSB.Children.Add($ef) | Out-Null
    $exitSB.Add_Completed({ if (-not $script:closing) { $frame.Continue = $false } })

    $enterSB.Add_Completed({
        $window.Opacity = 1.0
        $scaleTransform.ScaleX = 1.0
        $scaleTransform.ScaleY = 1.0
        $exitSB.Begin()
    })

    $card.Add_MouseLeftButtonDown({
        $script:closing = $true
        $exitSB.Stop()
        $cf = New-Object System.Windows.Media.Animation.DoubleAnimation
        $cf.From = $window.Opacity; $cf.To = 0.0
        $cf.Duration = [System.TimeSpan]::FromMilliseconds(120)
        [System.Windows.Media.Animation.Storyboard]::SetTarget($cf, $window)
        [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($cf, $propOpacity)
        $csb = New-Object System.Windows.Media.Animation.Storyboard
        $csb.Children.Add($cf) | Out-Null
        $csb.Add_Completed({ $frame.Continue = $false })
        $csb.Begin()
    })

    $window.Show()
    $enterSB.Begin()
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    $window.Close()
}

# ── Main event loop ──
while ($true) {
    try {
        $result = $watcher.WaitForChanged($changeTypes, 5000)
        if ($result.TimedOut) { continue }
    } catch {
        Start-Sleep -Milliseconds 1000
        continue
    }

    # Debounce — suppress duplicate FS events within 100ms
    $now = [DateTime]::Now
    if (($now - $script:lastEventTime).TotalMilliseconds -lt $debounceMs) { continue }
    $script:lastEventTime = $now

    # Let the write settle before reading
    Start-Sleep -Milliseconds 50

    if (-not (Test-Path $triggerFile)) { continue }
    try {
        $Message = (Get-Content $triggerFile -Encoding utf8 -Raw).Trim()
        if (-not $Message) { $Message = "Task completed" }
    } catch { continue }

    # Clear trigger file to prevent re-firing on next WatcherChanged cycle
    Remove-Item $triggerFile -Force -ErrorAction SilentlyContinue

    Show-Notification -Message $Message
}
