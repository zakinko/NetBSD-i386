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
  # Anything a function does not send to Out-Host becomes part of its
  # return value.  An earlier version wrote Get-Content here bare, so
  # none of XEmacs's output was ever shown, and the caller's -match ran
  # over an array instead of one string.
  Get-Content $out, $err -EA SilentlyContinue | Out-Host
  if ($p.ExitCode -ne $expect) { throw "$label failed (expected exit $expect)" }
  return [string]((Get-Content $out -Raw -EA SilentlyContinue) + "`n" +
                  (Get-Content $err -Raw -EA SilentlyContinue))
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
$exports = (& dumpbin /exports $ell) -join "`n"
$exports -split "`n" | Select-String -Pattern 'emodule_|_of_sample|unload_sample' | Out-Host

# Every name emodules.c looks up must be exported.  The first version of
# the init file missed emodule_coding and the gap only showed at
# load-module, as "Missing symbol".  Take the list from the loader itself
# so a name added there later is caught here, right after the link.
$loader = Get-Content (Join-Path $root 'src\emodules.c') -Raw
$wanted = [regex]::Matches($loader, '"(emodule_[a-z]+|[a-z_]+_%s)"') |
  ForEach-Object { $_.Groups[1].Value -replace '%s', 'sample' } |
  Sort-Object -Unique
Write-Host "loader looks up: $($wanted -join ' ')"
$missing = $wanted | Where-Object { $exports -notmatch "\b$_\b" }
if ($missing) { throw "not exported: $($missing -join ' ')" }

# The first load came back with exit 1, no output, and an empty log
# file.  Separate the three things that could be at fault before the
# real load: the -l path itself, the probe file, and load-module.
$hello = Join-Path $mod 'hello.el'
Set-Content -Path $hello -Value '(princ "hello from -l\n") (kill-emacs 3)'
$o = Invoke-XEmacs 'diag-l' @('-vanilla', '-l', $hello) 3
if ($o -notmatch 'hello from -l') { throw 'stdout from -l did not arrive' }

$probe = Join-Path $env:GITHUB_WORKSPACE 'ci\xemacs\module-load.el'
$env:SAMPLE_ELL = Join-Path $mod 'no-such.ell'
$o = Invoke-XEmacs 'diag-probe' @('-vanilla', '-l', $probe) 1
if ($o -notmatch 'error=') { throw 'probe did not reach its error branch' }

$env:SAMPLE_ELL = $ell
$o = Invoke-XEmacs 'load' @('-vanilla', '-l',
  (Join-Path $env:GITHUB_WORKSPACE 'ci\xemacs\module-load.el'))
foreach ($pat in 'loaded=t', 'sample-function=t',
                 'sample-boolean=nil', 'list-modules=.*sample') {
  if ($o -notmatch $pat) { throw "not seen: $pat" }
}
Write-Host 'sample module built by ellcc and loaded'
