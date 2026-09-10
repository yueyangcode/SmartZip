$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'Collect-Normal-Upgrade.cmd'
$text = [IO.File]::ReadAllText($path)
$line = @($text -split '\r?\n' | Where-Object { $_ -match '^"%SystemRoot%.* -Command "' })
if ($line.Count -ne 1 -or $line[0].Length -ge 8000) { throw 'Expected one CMD-safe, bounded PowerShell command.' }
$payload = [regex]::Match($line[0], ' -Command "(.*)"$').Groups[1].Value
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($payload, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$allowed = @('Get-CimInstance', 'Get-Content', 'ConvertFrom-Json', 'Get-FileHash', 'Test-Path', 'New-Item',
    'Join-Path', 'Get-ItemProperty', 'Select-Object', 'Get-AppxPackage', 'Get-AppxPackageManifest', 'Get-Item',
    'Get-ChildItem', 'Get-Process', 'ConvertTo-Json', 'Set-Content', 'Write-Output', 'Out-Null')
foreach ($command in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true)) {
    if ($command.GetCommandName() -notin $allowed) { throw "Unexpected command: $command" }
}
foreach ($forbidden in @('Add-AppxPackage', 'Remove-AppxPackage', 'Import-Certificate', 'Remove-Item',
    'Start-Process', 'Stop-Process', 'Set-ExecutionPolicy', 'CreateSubKey', 'SetValue(', 'File]::Delete', 'File]::Move')) {
    if ($text.Contains($forbidden)) { throw "Unexpected mutation: $forbidden" }
}
foreach ($required in @('Evidence already exists', 'Helper log changed during collection', 'helper-logs')) {
    if (!$text.Contains($required)) { throw "Missing evidence guard: $required" }
}
if ($env:USERNAME -eq 'WDAGUtilityAccount') { throw 'Run source tests on the build host, not inside the Sandbox.' }
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$guard = & $powershell -NoProfile -NonInteractive -Command $payload 2>&1 | Out-String
if ($LASTEXITCODE -ne 1 -or $guard -notmatch 'Sandbox required; host execution refused') { throw "Host guard failed: $guard" }
Write-Output 'PASS: syntax, bounded command, read-only command allowlist, evidence guards and Windows PowerShell 5.1 host refusal.'
