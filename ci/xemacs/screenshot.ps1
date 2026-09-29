# Save the whole screen to the PNG named by $args[0], and list the
# top-level windows that have a title, so a dialog nobody can see in the
# log shows up in both.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$bmp.Save($args[0])
$g.Dispose(); $bmp.Dispose()
Write-Host "screenshot: $($args[0])"
Get-Process | Where-Object { $_.MainWindowTitle } |
  ForEach-Object { "window: pid=$($_.Id) $($_.ProcessName): $($_.MainWindowTitle)" }
