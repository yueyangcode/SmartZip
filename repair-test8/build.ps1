$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$out = Join-Path $root 'build\repair-test8\payload'
New-Item -ItemType Directory -Force -Path $out | Out-Null
dotnet publish "$PSScriptRoot\Repair.csproj" -c Release -o $out -p:PublishTrimmed=true -p:TrimMode=link -p:TrimmerSingleWarn=false -p:TreatWarningsAsErrors=true -p:ILLinkTreatWarningsAsErrors=true -p:DebugType=None -p:DebugSymbols=false --nologo
if ($LASTEXITCODE -ne 0) { throw 'Repair publish failed.' }
$binary = Join-Path $out 'SmartZip-Repair-test8.exe'
$check = Start-Process -FilePath $binary -ArgumentList '--self-test' -WindowStyle Hidden -Wait -PassThru
if ($check.ExitCode -ne 0) { throw 'Repair safety self-tests failed.' }
# Existing development signing material only. No trust or certificate import.
$pass = Get-Content -LiteralPath "$root\.private\test-signing.password.dpapi" | ConvertTo-SecureString
$password = [Net.NetworkCredential]::new('', $pass).Password
try {
    & "$root\.tools\sdk\c\bin\10.0.26100.0\x64\signtool.exe" sign /fd SHA256 /f "$root\.private\test-signing.pfx" /p $password $binary
    if ($LASTEXITCODE -ne 0) { throw 'Repair signing failed.' }
} finally { $password = $null }
$dest = Join-Path $root 'dist\SmartZip-Repair-test8.exe'
Copy-Item -LiteralPath $binary -Destination $dest
$check = Start-Process -FilePath $dest -ArgumentList '--self-test' -WindowStyle Hidden -Wait -PassThru
if ($check.ExitCode -ne 0) { throw 'Signed repair safety self-tests failed.' }
Write-Output 'PASS: in-memory ownership, backup encoding, round-trip and scope guard tests. No repair executed.'
Get-Item -LiteralPath $dest | Select-Object FullName,Length
Get-FileHash -LiteralPath $dest | Format-List Hash
