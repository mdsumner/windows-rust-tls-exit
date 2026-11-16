# Run one R case under cdb, so the exit-time abort stops in the debugger
# with a stack, instead of vanishing (WER is off on the runners).
#   pwsh scripts/debug-case.ps1 <label> <R script> <case>
# Rterm.exe directly (Rscript -> R.exe -> Rterm.exe would hide it two
# processes down). -g: skip the initial breakpoint; -G: no final breakpoint,
# so a clean exit just exits. On the 0xC0000409 fail-fast, cdb runs the -c
# commands: the exception (its parameter is the FAST_FAIL code: 7 = abort,
# 5 = invalid CRT parameter, 2 = stack cookie, ...), the stack, the modules.
param(
  [Parameter(Mandatory = $true)][string]$Label,
  [Parameter(Mandatory = $true)][string]$Script,
  [Parameter(Mandatory = $true)][string]$Case
)
$ErrorActionPreference = 'Continue'
$cdb = @(
  "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\cdb.exe",
  "$env:ProgramFiles\Windows Kits\10\Debuggers\x64\cdb.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
Write-Host "::group::cdb $Label"
if (-not $cdb) { Write-Host 'cdb not found on this runner'; Write-Host '::endgroup::'; exit 0 }
$rbin = (& Rscript -e "cat(normalizePath(R.home('bin')))")
$rterm = Join-Path $rbin 'Rterm.exe'
Write-Host "cdb: $cdb"
Write-Host "Rterm: $rterm"
$env:_NT_SYMBOL_PATH = 'srv*C:\symcache*https://msdl.microsoft.com/download/symbols'
$cmds = '.lastevent; .exr -1; .ecxr; kn 80; lm o; q'
& $cdb -g -G -lines -c $cmds $rterm --no-echo --no-restore --vanilla "--file=$Script" --args $Case 2>&1 |
  ForEach-Object { Write-Host $_ }
Write-Host "cdb exit code: $LASTEXITCODE"
Write-Host '::endgroup::'
exit 0
