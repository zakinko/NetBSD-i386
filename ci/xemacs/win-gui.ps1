# Start a built XEmacs as a GUI program, type into it, screenshot it,
# and read back what it recorded.
#
#	$args[0]	the checkout (built)
#	$args[1]	a label for the output files
#	$args[2]	optional: a .ell to load inside the GUI

$ErrorActionPreference = 'Stop'
$root, $label, $ell = $args[0], $args[1], $args[2]
$out = Join-Path $env:GITHUB_WORKSPACE 'gui-out'
New-Item -ItemType Directory -Force $out | Out-Null
$log = Join-Path $out "$label.log"
Remove-Item $log -EA SilentlyContinue
$env:GUI_LOG = $log
$env:SAMPLE_ELL = if ($ell) { $ell } else { '' }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
function Save-Screen([string]$name) {
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
  $bmp.Save((Join-Path $out "$label-$name.png"))
  $g.Dispose(); $bmp.Dispose()
  Write-Host "screenshot: $label-$name.png ($($b.Width)x$($b.Height))"
}

$x = Join-Path $root 'src\xemacs.exe'
$probe = Join-Path $env:GITHUB_WORKSPACE 'ci\xemacs\gui-probe.el'
$p = Start-Process -FilePath $x -ArgumentList '-vanilla', '-l', $probe `
       -WorkingDirectory (Join-Path $root 'src') -PassThru

# Wait for the probe to say it is ready, not for a fixed time.
$deadline = (Get-Date).AddSeconds(60)
while (-not ((Test-Path $log) -and (Select-String -Path $log -Pattern '^ready' -Quiet))) {
  if ($p.HasExited) { throw "xemacs exited ($($p.ExitCode)) before it was ready" }
  if ((Get-Date) -gt $deadline) { Save-Screen 'stuck'; throw 'probe never became ready' }
  Start-Sleep -Milliseconds 500
}
$p.Refresh()
Write-Host "window title: '$($p.MainWindowTitle)'  handle: $($p.MainWindowHandle)"
Save-Screen 'started'

$sh = New-Object -ComObject WScript.Shell
if (-not $sh.AppActivate($p.Id)) { Write-Host 'AppActivate returned false' }
Start-Sleep -Seconds 1
$sh.SendKeys('hello from SendKeys')
Start-Sleep -Seconds 2
Save-Screen 'typed'

if (-not $p.WaitForExit(90000)) { Save-Screen 'hung'; $p.Kill(); throw 'xemacs did not exit' }
Write-Host "exit: $($p.ExitCode)"
Write-Host "--- $label.log ---"
Get-Content $log | Out-Host
$text = Get-Content $log -Raw
foreach ($pat in 'device-type=mswindows', 'menubar=t', 'typed: hello from SendKeys', 'exiting') {
  if ($text -notmatch [regex]::Escape($pat)) { throw "${label}: not seen: $pat" }
}
if ($ell -and $text -notmatch 'module=loaded') { throw "${label}: module did not load in the GUI" }
if ($p.ExitCode -ne 0) { throw "${label}: exit $($p.ExitCode)" }
Write-Host "${label}: GUI came up, took keyboard input, and exited cleanly"
