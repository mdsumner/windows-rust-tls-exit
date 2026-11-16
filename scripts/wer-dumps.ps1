# Ask Windows Error Reporting to keep a minidump of any crashing process in
# dumps/ (and make sure WER itself is on). Best effort: the runner may differ.
$ErrorActionPreference = 'Continue'
$dir = Join-Path $env:GITHUB_WORKSPACE 'dumps'
New-Item -ItemType Directory -Force $dir | Out-Null
$wer = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'
$k = Join-Path $wer 'LocalDumps'
New-Item -Path $k -Force | Out-Null
New-ItemProperty -Path $k -Name DumpFolder -PropertyType ExpandString -Value $dir -Force | Out-Null
New-ItemProperty -Path $k -Name DumpType -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $k -Name DumpCount -PropertyType DWord -Value 50 -Force | Out-Null
New-ItemProperty -Path $wer -Name Disabled -PropertyType DWord -Value 0 -Force | Out-Null
New-ItemProperty -Path $wer -Name DontShowUI -PropertyType DWord -Value 1 -Force | Out-Null
Get-ItemProperty $k | Format-List DumpFolder, DumpType, DumpCount
