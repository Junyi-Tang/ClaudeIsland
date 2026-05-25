# ── Notification daemon — watches trigger file, shows WPF pill instantly ──
# Start once per session:
#   Start-Process powershell -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", """path\to\notify-daemon.ps1""")

# ── Single-instance guard ──
$daemonLock = "$env:TEMP\claude_notify_daemon.lock"
$myPid = $PID
if (Test-Path $daemonLock) {
    $existingPid = [int](Get-Content $daemonLock -Raw).Trim()
    try { $existing = Get-Process -Id $existingPid -ErrorAction SilentlyContinue } catch { $existing = $null }
    if ($existing) { exit 0 }
}
$myPid | Out-File $daemonLock -Force

# ── Ensure STA mode for WPF ──
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { exit 1 }

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

# Windows 11 native rounded corners via DWM
try {
    $null = [Win32.DwmUtil]
} catch {
    $null = Add-Type -MemberDefinition @"
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
"@ -Name "DwmUtil" -Namespace "Win32" -PassThru
}

$triggerFile = "$env:TEMP\claude_notify_trigger.txt"
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$assetDir = Join-Path $scriptDir "assets"
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

# Pre-warm theme tokens — warm-tinted neutrals, no pure black or white
$cardBg  = [System.Windows.Media.Color]::FromRgb(12, 10, 8)
$warmWht = [System.Windows.Media.Color]::FromRgb(252, 249, 246)
$slate   = [System.Windows.Media.Color]::FromRgb(160, 152, 140)
$dim     = [System.Windows.Media.Color]::FromRgb(105, 100, 95)
$faint   = [System.Windows.Media.Color]::FromRgb(115, 110, 105)
$accentBrush = New-Object System.Windows.Media.LinearGradientBrush
$accentBrush.StartPoint = New-Object System.Windows.Point(0, 0)
$accentBrush.EndPoint = New-Object System.Windows.Point(0, 1)
$a1 = New-Object System.Windows.Media.GradientStop([System.Windows.Media.Color]::FromRgb(239, 106, 75), 0.0)
$a2 = New-Object System.Windows.Media.GradientStop([System.Windows.Media.Color]::FromRgb(217, 83, 53), 1.0)
$accentBrush.GradientStops.Add($a1) | Out-Null
$accentBrush.GradientStops.Add($a2) | Out-Null
$iconBgBrush = New-Object System.Windows.Media.SolidColorBrush(
    [System.Windows.Media.Color]::FromArgb(30, 252, 249, 246)
)
$propOpacity = New-Object System.Windows.PropertyPath("Opacity")
$propScaleX  = New-Object System.Windows.PropertyPath("ScaleX")
$propScaleY  = New-Object System.Windows.PropertyPath("ScaleY")

$lastTrigger = $null

while ($true) {
    # Update lock timestamp so other instances know we're alive
    $myPid | Out-File $daemonLock -Force

    if (Test-Path $triggerFile) {
        $current = (Get-Item $triggerFile).LastWriteTime
        if ($current -ne $lastTrigger) {
            $lastTrigger = $current
            $Message = (Get-Content $triggerFile -Encoding utf8 -Raw).Trim()
            if (-not $Message) { $Message = "Task completed" }
            $showTime = Get-Date
            $screen = [System.Windows.SystemParameters]::WorkArea

            try {
                # ── Window ──
                $window = New-Object System.Windows.Window
                $window.WindowStyle = 'None'
                $window.AllowsTransparency = $true
                $window.Background = New-Object System.Windows.Media.SolidColorBrush($cardBg)
                $window.Topmost = $true
                $window.ShowInTaskbar = $false
                $window.ShowActivated = $false
                $window.Width = 400
                $window.Height = 90
                $window.Left = $screen.Width - $window.Width - 12
                $window.Top = $screen.Height - $window.Height - 24
                $window.ResizeMode = 'NoResize'
                $window.Cursor = 'None'

                # ── Card ──
                $card = New-Object System.Windows.Controls.Border
                $card.CornerRadius = New-Object System.Windows.CornerRadius(16)
                $card.Background = New-Object System.Windows.Media.SolidColorBrush($cardBg)
                $card.BorderThickness = New-Object System.Windows.Thickness(0)
                $card.ClipToBounds = $true
                $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
                $shadow.BlurRadius = 40; $shadow.Opacity = 0.2; $shadow.ShadowDepth = 6; $shadow.Direction = 270
                $card.Effect = $shadow
                $card.Cursor = [System.Windows.Input.Cursors]::Hand

                # ── Inner grid ──
                $innerGrid = New-Object System.Windows.Controls.Grid
                $innerGrid.Margin = New-Object System.Windows.Thickness(18, 0, 18, 0)
                $iconCol = New-Object System.Windows.Controls.ColumnDefinition
                $iconCol.Width = [System.Windows.GridLength]::new(60)
                $textCol = New-Object System.Windows.Controls.ColumnDefinition
                $textCol.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
                $badgeCol = New-Object System.Windows.Controls.ColumnDefinition
                $badgeCol.Width = [System.Windows.GridLength]::Auto
                $innerGrid.ColumnDefinitions.Add($iconCol) | Out-Null
                $innerGrid.ColumnDefinitions.Add($textCol) | Out-Null
                $innerGrid.ColumnDefinitions.Add($badgeCol) | Out-Null

                # ── Icon badge ──
                $iconBadge = New-Object System.Windows.Controls.Border
                $iconBadge.Width = 44; $iconBadge.Height = 44
                $iconBadge.CornerRadius = New-Object System.Windows.CornerRadius(10)
                $iconBadge.Background = $iconBgBrush
                $iconBadge.BorderThickness = New-Object System.Windows.Thickness(0)
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
                $iconImage.Width = 32; $iconImage.Height = 32
                $iconBadge.Child = $iconImage
                $innerGrid.Children.Add($iconBadge) | Out-Null

                # ── Text stack ──
                $textStack = New-Object System.Windows.Controls.StackPanel
                $textStack.VerticalAlignment = 'Center'
                $textStack.Margin = New-Object System.Windows.Thickness(14, 0, 0, 0)
                [System.Windows.Controls.Grid]::SetColumn($textStack, 1)

                $title = New-Object System.Windows.Controls.TextBlock
                $title.Text = "Claude Code"
                $title.Foreground = New-Object System.Windows.Media.SolidColorBrush($warmWht)
                $title.FontFamily = "Segoe UI"; $title.FontWeight = 'Bold'; $title.FontSize = 18

                $body = New-Object System.Windows.Controls.TextBlock
                $body.Text = $Message
                $body.Foreground = New-Object System.Windows.Media.SolidColorBrush($slate)
                $body.FontFamily = "Segoe UI"; $body.FontSize = 13.5
                $body.Margin = New-Object System.Windows.Thickness(0, 5, 0, 0)
                $body.TextWrapping = 'NoWrap'; $body.TextTrimming = 'CharacterEllipsis'

                $hint = New-Object System.Windows.Controls.TextBlock
                $hint.Text = ([char]0x2022 + " Click to dismiss")
                $hint.Foreground = New-Object System.Windows.Media.SolidColorBrush($dim)
                $hint.FontFamily = "Segoe UI"; $hint.FontSize = 11
                $hint.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)

                $textStack.Children.Add($title) | Out-Null
                $textStack.Children.Add($body) | Out-Null
                $textStack.Children.Add($hint) | Out-Null
                $innerGrid.Children.Add($textStack) | Out-Null

                # ── Timestamp ──
                $statusBadge = New-Object System.Windows.Controls.TextBlock
                $statusBadge.Text = $showTime.ToString("HH:mm")
                $statusBadge.Foreground = New-Object System.Windows.Media.SolidColorBrush($faint)
                $statusBadge.FontFamily = "Segoe UI"; $statusBadge.FontSize = 11
                $statusBadge.VerticalAlignment = 'Top'; $statusBadge.HorizontalAlignment = 'Right'
                $statusBadge.Margin = New-Object System.Windows.Thickness(8, 2, 0, 0)
                [System.Windows.Controls.Grid]::SetColumn($statusBadge, 2)
                $innerGrid.Children.Add($statusBadge) | Out-Null

                $card.Child = $innerGrid
                $window.Content = $card

                # ── Entrance transform ──
                $scaleTransform = New-Object System.Windows.Media.ScaleTransform(0.85, 0.85)
                $card.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
                $card.RenderTransform = $scaleTransform
                $window.Opacity = 0

                # ── Storyboards ──
                $enterSB = New-Object System.Windows.Media.Animation.Storyboard
                $eo = New-Object System.Windows.Media.Animation.DoubleAnimation
                $eo.From = 0; $eo.To = 1.0; $eo.Duration = [System.TimeSpan]::FromMilliseconds(250)
                [System.Windows.Media.Animation.Storyboard]::SetTarget($eo, $window)
                [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($eo, $propOpacity)
                $enterSB.Children.Add($eo) | Out-Null

                $esx = New-Object System.Windows.Media.Animation.DoubleAnimation
                $esx.From = 0.85; $esx.To = 1.0; $esx.Duration = [System.TimeSpan]::FromMilliseconds(250)
                [System.Windows.Media.Animation.Storyboard]::SetTarget($esx, $scaleTransform)
                [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($esx, $propScaleX)
                $enterSB.Children.Add($esx) | Out-Null

                $esy = New-Object System.Windows.Media.Animation.DoubleAnimation
                $esy.From = 0.85; $esy.To = 1.0; $esy.Duration = [System.TimeSpan]::FromMilliseconds(250)
                [System.Windows.Media.Animation.Storyboard]::SetTarget($esy, $scaleTransform)
                [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($esy, $propScaleY)
                $enterSB.Children.Add($esy) | Out-Null

                $frame = New-Object System.Windows.Threading.DispatcherFrame
                $closing = $false

                $exitSB = New-Object System.Windows.Media.Animation.Storyboard
                $ef = New-Object System.Windows.Media.Animation.DoubleAnimation
                $ef.From = 1.0; $ef.To = 0.0
                $ef.Duration = [System.TimeSpan]::FromMilliseconds(187)
                $ef.BeginTime = [System.TimeSpan]::FromSeconds(30)
                [System.Windows.Media.Animation.Storyboard]::SetTarget($ef, $window)
                [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($ef, $propOpacity)
                $exitSB.Children.Add($ef) | Out-Null
                $exitSB.Add_Completed({ if (-not $closing) { $frame.Continue = $false } })

                $enterSB.Add_Completed({
                    $window.Opacity = 1.0
                    $scaleTransform.ScaleX = 1.0
                    $scaleTransform.ScaleY = 1.0
                    $exitSB.Begin()
                })

                # ── Hover feedback: subtle lighten on enter, restore on leave ──
                $card.Add_MouseEnter({
                    $sb = New-Object System.Windows.Media.Animation.Storyboard
                    $ca = New-Object System.Windows.Media.Animation.ColorAnimation
                    $ca.To = [System.Windows.Media.Color]::FromRgb(28, 25, 22)
                    $ca.Duration = [System.TimeSpan]::FromMilliseconds(180)
                    [System.Windows.Media.Animation.Storyboard]::SetTarget($ca, $card)
                    [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($ca,
                        New-Object System.Windows.PropertyPath("Background.Color"))
                    $sb.Children.Add($ca) | Out-Null
                    $sb.Begin()
                })
                $card.Add_MouseLeave({
                    $sb = New-Object System.Windows.Media.Animation.Storyboard
                    $ca = New-Object System.Windows.Media.Animation.ColorAnimation
                    $ca.To = $cardBg
                    $ca.Duration = [System.TimeSpan]::FromMilliseconds(250)
                    [System.Windows.Media.Animation.Storyboard]::SetTarget($ca, $card)
                    [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($ca,
                        New-Object System.Windows.PropertyPath("Background.Color"))
                    $sb.Children.Add($ca) | Out-Null
                    $sb.Begin()
                })

                $card.Add_MouseLeftButtonDown({
                    $closing = $true
                    $exitSB.Stop()
                    $cf = New-Object System.Windows.Media.Animation.DoubleAnimation
                    $cf.From = $window.Opacity; $cf.To = 0.0
                    $cf.Duration = [System.TimeSpan]::FromMilliseconds(150)
                    [System.Windows.Media.Animation.Storyboard]::SetTarget($cf, $window)
                    [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($cf, $propOpacity)
                    $csb = New-Object System.Windows.Media.Animation.Storyboard
                    $csb.Children.Add($cf) | Out-Null
                    $csb.Add_Completed({ $frame.Continue = $false })
                    $csb.Begin()
                })

                $window.Show()
                try {
                    $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
                    $pref = 3
                    [Win32.DwmUtil]::DwmSetWindowAttribute($helper.Handle, 33, [ref]$pref, 4)
                } catch {}
                [System.Media.SystemSounds]::Asterisk.Play()
                $enterSB.Begin()
                [System.Windows.Threading.Dispatcher]::PushFrame($frame)
                $window.Close()
            } catch {
                # Notification failed — log and continue watching
                if ($window) { try { $window.Close() } catch {} }
            }
        }
    }
    Start-Sleep -Milliseconds 100
}
