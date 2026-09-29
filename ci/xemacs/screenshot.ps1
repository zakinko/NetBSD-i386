# Save the whole screen to the PNG named by $args[0], and list the
# top-level windows that have a title.  A window whose title says Error
# is brought to the front first, and the text of everything inside it is
# printed: the ninth MinGW probe found an "xemacs: Error" message box
# hidden behind the terminal, where a screenshot could not show it.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$sh = New-Object -ComObject WScript.Shell
$procs = Get-Process | Where-Object { $_.MainWindowTitle }
foreach ($p in $procs) {
  "window: pid=$($p.Id) $($p.ProcessName): $($p.MainWindowTitle)"
  if ($p.MainWindowTitle -match 'Error') {
    [void]$sh.AppActivate($p.Id)
    Start-Sleep -Milliseconds 800
    $el = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
    $all = $el.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                       [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($c in $all) {
      $n = $c.Current.Name
      if ($n) { "  text: $n" }
    }
  }
}

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$bmp.Save($args[0])
$g.Dispose(); $bmp.Dispose()
"screenshot: $($args[0])"
