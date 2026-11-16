# Run one command under cdb, so an exit-time abort stops in the debugger
# with a stack (as debug-case.ps1 does for Rterm.exe).
#   pwsh scripts/debug-exe.ps1 <label> <exe> [args...]
# The exe's directory is on the symbol path, so an MSVC build's PDBs name
# the frames (aws-lc's C included); GNU builds' DWARF is invisible to cdb.
param(
  [Parameter(Mandatory = $true)][string]$Label,
  [Parameter(Mandatory = $true)][string]$Exe,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$CaseArgs
)
$ErrorActionPreference = 'Continue'
$cdb = @(
  "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\cdb.exe",
  "$env:ProgramFiles\Windows Kits\10\Debuggers\x64\cdb.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
Write-Host "::group::cdb $Label"
if (-not $cdb) { Write-Host 'cdb not found on this runner'; Write-Host '::endgroup::'; exit 0 }
$exePath = (Resolve-Path $Exe).Path
$dir = Split-Path $exePath
$env:_NT_SYMBOL_PATH = "$dir;srv*C:\symcache*https://msdl.microsoft.com/download/symbols"
$cmds = '.lastevent; .exr -1; .ecxr; kn 40; lm o; q'
& $cdb -g -G -lines -c $cmds $exePath @CaseArgs 2>&1 | ForEach-Object { Write-Host $_ }
Write-Host "cdb exit code: $LASTEXITCODE"
Write-Host '::endgroup::'
exit 0
