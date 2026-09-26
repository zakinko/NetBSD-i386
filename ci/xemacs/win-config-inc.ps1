# Put a minimal nt/config.inc in place.  Used by every Windows job, so
# the tree built for make check is configured the same way as the one
# the module job builds.
#
#	$args[0]	the XEmacs checkout

$ErrorActionPreference = 'Stop'
# Push/Pop: a Set-Location in a script outlives it in the caller's
# session, and the second call of two, made with a relative path, then
# could not find this script.
Push-Location (Join-Path $args[0] 'nt')
try {
Copy-Item config.inc.samp config.inc
# No optional libraries.  The names are the ones config.inc.samp uses
# (there is no HAVE_ZLIB).
$c = Get-Content config.inc
foreach ($v in 'HAVE_XPM','HAVE_GIF','HAVE_PNG','HAVE_JPEG','HAVE_TIFF','HAVE_XFACE') {
  $c = $c -replace "^$v=1", "$v=0"
}
# The default PERL points into Cygwin; use the runner's.
$perl = (Get-Command perl -ErrorAction SilentlyContinue).Source
if (-not $perl) { throw 'no perl on PATH' }
Write-Host "perl: $perl"
$c = $c -replace '^PERL=.*', ("PERL=" + $perl)
Set-Content config.inc $c
Select-String -Path config.inc -Pattern '^(HAVE_|UNICODE_|PERL=)' | Out-Host
} finally { Pop-Location }
