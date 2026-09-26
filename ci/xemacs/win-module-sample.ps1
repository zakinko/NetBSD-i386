# Build modules/sample/external with ellcc on MSVC and load it.
#
# Every XEmacs run goes through lib-src/i.exe: xemacs.exe is linked
# -subsystem:windows, so started directly from a console it returns no
# output and never returns control.  Each run has its own time limit
# for the same reason.

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:GITHUB_WORKSPACE 'xemacs'
$i    = Join-Path $root 'lib-src\i.exe'
$x    = Join-Path $root 'src\xemacs.exe'
$el   = Join-Path $root 'lisp\ellcc.el'
$mod  = Join-Path $root 'modules\sample\external'

function Invoke-XEmacs([string]$label, [string[]]$rest, [int]$expect = 0) {
  $out = Join-Path $mod "$label.out"
  $err = Join-Path $mod "$label.err"
  $p = Start-Process -FilePath $i -ArgumentList (@($x, '-batch') + $rest) `
         -WorkingDirectory $mod -NoNewWindow -PassThru `
         -RedirectStandardOutput $out -RedirectStandardError $err
  if (-not $p.WaitForExit(300000)) {
    $p.Kill(); Get-Content $out, $err -EA SilentlyContinue
    throw "${label}: no return in 300 s"
  }
  # A crash shows as an NTSTATUS such as 0xC0000005, not as 1.
  Write-Host ("=== $label (exit {0} = 0x{0:X8}) ===" -f $p.ExitCode)
  Get-Content $out, $err -EA SilentlyContinue
  if ($env:SAMPLE_LOG -and (Test-Path $env:SAMPLE_LOG)) {
    Write-Host "--- $env:SAMPLE_LOG ---"; Get-Content $env:SAMPLE_LOG
  }
  if ($p.ExitCode -ne $expect) { throw "$label failed (expected exit $expect)" }
  return (Get-Content $out -Raw -EA SilentlyContinue)
}

function Invoke-Ellcc([string]$label, [string[]]$rest) {
  Invoke-XEmacs $label (@('--script', $el, '--', '--mode=verbose') + $rest)
}

# A title with a space would be split by Start-Process, which joins
# ArgumentList without quoting.
Invoke-Ellcc 'init' @('--mode=init', '--mod-output=sample_i.c',
  '--mod-name=sample', '--mod-version=0.0.1', '--mod-title=Sample',
  'sample.c') | Out-Null
Write-Host '--- sample_i.c ---'
Get-Content (Join-Path $mod 'sample_i.c')

Invoke-Ellcc 'cc-sample'   @('--mode=compile', '-c', 'sample.c')   | Out-Null
Invoke-Ellcc 'cc-sample_i' @('--mode=compile', '-c', 'sample_i.c') | Out-Null
Invoke-Ellcc 'link' @('--mode=link', '--mod-output=sample.ell',
  'sample.obj', 'sample_i.obj') | Out-Null

$ell = Join-Path $mod 'sample.ell'
if (-not (Test-Path $ell)) { throw 'sample.ell was not produced' }
$len = (Get-Item $ell).Length
Write-Host "sample.ell: $len bytes"
if ($len -lt 1024) { throw "sample.ell is only $len bytes" }

Write-Host '--- exports of sample.ell ---'
& dumpbin /exports $ell | Select-String -Pattern 'emodule_|_of_sample|unload_sample'

# The first load came back with exit 1, no output, and an empty log
# file.  Separate the three things that could be at fault before the
# real load: the -l path itself, the probe file, and load-module.
$hello = Join-Path $mod 'hello.el'
Set-Content -Path $hello -Value '(princ "hello from -l\n") (kill-emacs 3)'
Invoke-XEmacs 'diag-l' @('-vanilla', '-l', $hello) 3 | Out-Null

$probe = Join-Path $env:GITHUB_WORKSPACE 'ci\xemacs\module-load.el'
$env:SAMPLE_LOG = Join-Path $mod 'probe-only.log'
$env:SAMPLE_ELL = Join-Path $mod 'no-such.ell'
Invoke-XEmacs 'diag-probe' @('-vanilla', '-l', $probe) 1 | Out-Null

$env:SAMPLE_ELL = $ell
$env:SAMPLE_LOG = Join-Path $mod 'load.log'
$o = Invoke-XEmacs 'load' @('-vanilla', '-l',
  (Join-Path $env:GITHUB_WORKSPACE 'ci\xemacs\module-load.el'))
foreach ($pat in 'loaded=t', 'sample-function=t',
                 'sample-boolean=nil', 'list-modules=.*sample') {
  if ($o -notmatch $pat) { throw "not seen: $pat" }
}
Write-Host 'sample module built by ellcc and loaded'
