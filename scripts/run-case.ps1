# Run one command, record its exit code, and collect what Windows saw.
#   pwsh scripts/run-case.ps1 <label> <exe> [args...]
# Never fails itself, so every case runs. Appends "label | exit | hex" to
# results.md, prints the Application Error / WER events since the start
# (faulting module, exception code, offset), and leaves any minidump in
# dumps/ (WER LocalDumps, configured by the workflow).
param(
  [Parameter(Mandatory = $true)][string]$Label,
  [Parameter(Mandatory = $true)][string]$Exe,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$CaseArgs
)
$ErrorActionPreference = 'Continue'
$start = (Get-Date).AddSeconds(-1)
Write-Host "::group::$Label"
Write-Host "> $Exe $($CaseArgs -join ' ')"
& $Exe @CaseArgs 2>&1 | ForEach-Object { Write-Host $_ }
$code = $LASTEXITCODE
$hex = '0x{0:X8}' -f ([int32]$code)
Write-Host "exit code: $code ($hex)"
Start-Sleep -Seconds 3
$events = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $start } -ErrorAction SilentlyContinue |
  Where-Object { $_.ProviderName -in @('Application Error', 'Windows Error Reporting') }
$fault = ''
foreach ($e in $events) {
  Write-Host "--- event $($e.Id) $($e.ProviderName) $($e.TimeCreated)"
  Write-Host $e.Message
  if ($e.Id -eq 1000 -and -not $fault) {
    $m = [regex]::Match($e.Message, 'Faulting module name: ([^,\r\n]+)')
    $x = [regex]::Match($e.Message, 'Exception code: (0x[0-9a-fA-F]+)')
    $o = [regex]::Match($e.Message, 'Fault offset: (0x[0-9a-fA-F]+)')
    $fault = "$($m.Groups[1].Value) $($x.Groups[1].Value) +$($o.Groups[1].Value)"
  }
}
Write-Host "::endgroup::"
$status = if ($code -eq 0) { 'ok' } else { 'FAIL' }
"| $Label | $status | $code | $hex | $fault |" | Out-File -Append -Encoding utf8 results.md
exit 0
