# What a DLL imports (which system DLLs, and the RNG entry points) and how
# many symbols it exports, with whichever objdump the runner has.
#   pwsh scripts/pe-info.ps1 <label> <dll>
# Best effort: never fails the job.
param(
  [Parameter(Mandatory = $true)][string]$Label,
  [Parameter(Mandatory = $true)][string]$Dll
)
$ErrorActionPreference = 'Continue'
Write-Host "::group::PE $Label"
$rt = if ($env:RTOOLS45_HOME) { $env:RTOOLS45_HOME } else { 'C:\rtools45' }
$od = @(
  (Join-Path $rt 'x86_64-w64-mingw32.static.posix\bin\objdump.exe'),
  "$env:ProgramFiles\LLVM\bin\llvm-objdump.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $od) { Write-Host 'no objdump on this runner'; Write-Host '::endgroup::'; exit 0 }
Write-Host "$Dll ($((Get-Item $Dll).Length) bytes), $od"
$p = & $od -p $Dll 2>&1
Write-Host 'Imported DLLs:'
$p | Select-String -Pattern 'DLL Name:' | ForEach-Object { Write-Host "  $($_.Line.Trim())" }
Write-Host 'RNG imports:'
$p | Select-String -Pattern 'ProcessPrng|BCryptGenRandom|SystemFunction036|RtlGenRandom' |
  ForEach-Object { Write-Host "  $($_.Line.Trim())" }
$ex = $p | Select-String -Pattern '^\s*\[\s*\d+\]\s'
Write-Host "Export table entries: $($ex.Count)"
$ex | Select-Object -First 8 | ForEach-Object { Write-Host "  $($_.Line.Trim())" }
Write-Host '::endgroup::'
exit 0
