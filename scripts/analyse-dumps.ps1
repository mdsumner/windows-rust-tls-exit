# For each minidump in dumps/: the exception record and the faulting
# thread's stack, via cdb (Debugging Tools for Windows) if the runner has it.
# Rust frames built with the GNU toolchain have no PDB, so expect module+offset
# there; Windows system frames resolve through the Microsoft symbol server.
$ErrorActionPreference = 'Continue'
$dumps = Get-ChildItem (Join-Path $env:GITHUB_WORKSPACE 'dumps') -Filter '*.dmp' -ErrorAction SilentlyContinue
if (-not $dumps) { Write-Host 'no minidumps'; exit 0 }
$cdb = @(
  "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\cdb.exe",
  "$env:ProgramFiles\Windows Kits\10\Debuggers\x64\cdb.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
foreach ($d in $dumps) {
  Write-Host "::group::$($d.Name) ($([math]::Round($d.Length / 1MB, 1)) MB)"
  if ($cdb) {
    & $cdb -z $d.FullName -y 'srv*C:\symcache*https://msdl.microsoft.com/download/symbols' -c '.lines -d; .exr -1; .ecxr; kn 60; lm; q' 2>&1 |
      Select-Object -Last 160 | ForEach-Object { Write-Host $_ }
  } else {
    Write-Host 'cdb not found; download the dumps artifact'
  }
  Write-Host '::endgroup::'
}
exit 0
