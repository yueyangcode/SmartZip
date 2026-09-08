$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$out = Join-Path $root 'build\preflight-diagnostic\payload'
New-Item -ItemType Directory -Force -Path $out | Out-Null
& "$root\diagnostics\Safety.Tests.ps1"
dotnet publish "$PSScriptRoot\PreflightProbe.csproj" -c Release -o $out -p:PublishTrimmed=true -p:TrimMode=link -p:TrimmerSingleWarn=false -p:TreatWarningsAsErrors=true -p:ILLinkTreatWarningsAsErrors=true -p:DebugType=None -p:DebugSymbols=false --nologo
if ($LASTEXITCODE -ne 0) { throw 'Diagnostic publish failed.' }
$probe = Start-Process -FilePath "$out\DeploymentHelper.exe" -ArgumentList 'self-test --no-ui' -WindowStyle Hidden -Wait -PassThru
if ($probe.ExitCode -ne 0) { throw 'Diagnostic predicate tests failed.' }
Copy-Item -LiteralPath "$root\build\payload\Licenses\DotNet-MIT.txt","$root\build\payload\Licenses\DotNet-ThirdParty.txt","$root\licenses\CsWinRT.txt" -Destination $out
# Use the existing development signing material, only in memory; never trust/import it.
$pass = Get-Content -LiteralPath "$root\.private\test-signing.password.dpapi" | ConvertTo-SecureString
$password = [Net.NetworkCredential]::new('', $pass).Password
$pfx = "$root\.private\test-signing.pfx"
$signer = "$root\.tools\sdk\c\bin\10.0.26100.0\x64\signtool.exe"
try {
    & $signer sign /fd SHA256 /f $pfx /p $password "$out\DeploymentHelper.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Diagnostic helper signing failed.' }
    & "$root\.tools\inno\tools\ISCC.exe" "$PSScriptRoot\PreflightDiagnostic.iss"
    if ($LASTEXITCODE -ne 0) { throw 'Diagnostic wrapper compile failed.' }
    & $signer sign /fd SHA256 /f $pfx /p $password "$root\dist\SmartZip-Preflight-Diagnostic.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Diagnostic wrapper signing failed.' }
} finally { $password = $null }
Get-Item "$root\dist\SmartZip-Preflight-Diagnostic.exe" | Select-Object FullName,Length
Get-FileHash "$root\dist\SmartZip-Preflight-Diagnostic.exe" | Format-List Hash
