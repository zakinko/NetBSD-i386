# make check on Windows came back with two files different between the
# base and the patched tree, each built and run in its own job:
#
#	os-tests.el              46/62  ->   44/62
#	query-coding-tests.el  4592/4636 -> 4076/4120
#
# The patch touches neither process handling nor coding systems.  Run
# both trees in one job, on one machine, alternating, several rounds, so
# a difference that follows the tree can be told from one that follows
# the machine or the round.
#
#	$args[0]	base checkout (built)
#	$args[1]	patched checkout (built)

$ErrorActionPreference = 'Stop'
$trees = [ordered]@{ base = $args[0]; patched = $args[1] }
$files = 'os-tests.el', 'query-coding-tests.el'
$count = Join-Path $env:GITHUB_WORKSPACE 'ci\xemacs\coding-system-count.el'
$rows = @()

function Run-XEmacs([string]$root, [string[]]$rest) {
  $out = Join-Path $root 'recheck.out'
  $err = Join-Path $root 'recheck.err'
  $p = Start-Process -FilePath (Join-Path $root 'lib-src\i.exe') `
         -ArgumentList (@((Join-Path $root 'src\xemacs.exe'), '-vanilla', '-batch') + $rest) `
         -WorkingDirectory (Join-Path $root 'src') -NoNewWindow -PassThru `
         -RedirectStandardOutput $out -RedirectStandardError $err
  if (-not $p.WaitForExit(900000)) { $p.Kill(); throw "no return in 900 s" }
  return [string]((Get-Content $out -Raw -EA SilentlyContinue) + "`n" +
                  (Get-Content $err -Raw -EA SilentlyContinue))
}

foreach ($round in 1..3) {
  foreach ($tree in $trees.Keys) {
    $root = $trees[$tree]
    $cs = Run-XEmacs $root @('-l', $count)
    $n = if ($cs -match 'coding-systems=(\d+)') { $Matches[1] } else { '?' }
    $tests = $files | ForEach-Object { Join-Path $root "tests\automated\$_" }
    $o = Run-XEmacs $root (@('-l', 'test-harness', '-f', 'batch-test-emacs') + $tests)
    foreach ($f in $files) {
      $m = [regex]::Match($o, [regex]::Escape($f) + ':?\s+(\d+)\s+of\s+(\d+)\s+tests successful')
      $r = if ($m.Success) { "$($m.Groups[1].Value)/$($m.Groups[2].Value)" } else { 'no summary' }
      $rows += [pscustomobject]@{ round = $round; tree = $tree; file = $f; result = $r; coding_systems = $n }
    }
    if ($round -eq 1) {
      # The os-tests failures, once per tree, to set against each other.
      Write-Host "--- $tree, round 1: os-tests FAIL lines ---"
      ($o -split "`n") | Where-Object { $_ -match '^FAIL' } | Out-Host
    }
  }
}
$rows | Format-Table -AutoSize | Out-Host
