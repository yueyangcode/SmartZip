param([ValidateSet('Test','Release')][string]$Signing='Test',[string]$Version='0.1.0.9',
 [ValidateSet('','after-stage','after-package','before-commit','after-state')][string]$FaultAt='')
$ErrorActionPreference='Stop'
$parsedVersion=$null
if(![version]::TryParse($Version,[ref]$parsedVersion) -or $parsedVersion.Revision -lt 0 -or $parsedVersion.ToString(4) -cne $Version -or @($parsedVersion.Major,$parsedVersion.Minor,$parsedVersion.Build,$parsedVersion.Revision | Where-Object {$_ -gt 65535}).Count){throw 'Use an exact four-part MSIX version with each component 0..65535.'}
if($Signing -eq 'Release'){
  if($FaultAt){throw 'Fault injection is forbidden in Release builds.'}
  if(!$env:SMARTZIP_SIGN_PFX -or !$env:SMARTZIP_SIGN_PASSWORD -or !$env:SMARTZIP_PUBLISHER){throw 'Release blocked: supply a trusted code-signing PFX, SMARTZIP_SIGN_PASSWORD and exact SMARTZIP_PUBLISHER. No test-key fallback.'}
  $releaseCert=[Security.Cryptography.X509Certificates.X509Certificate2]::new($env:SMARTZIP_SIGN_PFX,$env:SMARTZIP_SIGN_PASSWORD,[Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
  $releaseChain=[Security.Cryptography.X509Certificates.X509Chain]::new()
  $releaseChain.ChainPolicy.ApplicationPolicy.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
  if(!$releaseCert.HasPrivateKey -or $releaseCert.Subject -ne $env:SMARTZIP_PUBLISHER -or $releaseCert.Subject -eq $releaseCert.Issuer -or !$releaseChain.Build($releaseCert)){throw 'Release certificate must have a private key, match the Publisher and validate to existing system trust. No certificate is imported.'}
}
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE='false'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE='1'
$root=$PSScriptRoot
Set-Location -LiteralPath $root
& "$root\tests\UninstallOrder.Tests.ps1"
& "$root\tests\LegacyRegistration.Tests.ps1"
& "$root\tests\ChineseInstaller.Tests.ps1"
dotnet run --project "$root\tests\InstallPathTests" -c Release
if($LASTEXITCODE -ne 0){throw 'Install path tests failed.'}
dotnet run --project "$root\tests\UpgradeTests" -c Release
if($LASTEXITCODE -ne 0){throw 'Upgrade tests failed.'}
function CheckExit([string]$step){if($LASTEXITCODE -ne 0){throw "$step failed ($LASTEXITCODE)"}}
function Sign([string]$path){
  $timestampArgs=if($Signing -eq 'Release'){@('/tr','http://timestamp.digicert.com','/td','SHA256')}else{@()}
  & "$sdk\signtool.exe" sign /fd SHA256 /f $pfx /p $password @timestampArgs $path;CheckExit "sign $([IO.Path]::GetFileName($path))"
}
& "$root\bootstrap.ps1"
foreach($a in @(@('inno','inno'),@('sdk','sdk'),@('sdk-x64','sdk-x64'))){if(!(Test-Path ".tools\$($a[1])")){Expand-Archive "downloads\$($a[0]).zip" ".tools\$($a[1])"}}
if(!(Test-Path '.tools\llvm-mingw-20260826-ucrt-x86_64')){Expand-Archive downloads\llvm.zip .tools}
if(!(Test-Path vendor\AutoHotkey)){Expand-Archive downloads\ahk.zip vendor\AutoHotkey}
if(!(Get-ChildItem vendor -Directory -Filter 'SmartZip-*')){Expand-Archive downloads\smartzip.zip vendor}
$llvm="$root\.tools\llvm-mingw-20260826-ucrt-x86_64\bin"
$sdk="$root\.tools\sdk\c\bin\10.0.26100.0\x64"
$inno="$root\.tools\inno\tools\ISCC.exe"
& "$root\tests\DirectoryWizard.Tests.ps1"
$payload="$root\build\payload"
New-Item -ItemType Directory -Force -Path $payload,"$payload\Engine","$payload\Backend","$payload\Assets","$payload\Licenses","$payload\Sources","$root\build\identity","$root\build\tests","$root\dist","$root\.private" | Out-Null
& "$root\packaging\MakeAssets.ps1" -Destination "$payload\Assets"
if(!(Test-Path downloads\7zr.exe)){Invoke-WebRequest 'https://github.com/ip7z/7zip/releases/download/26.03/7zr.exe' -OutFile downloads\7zr.exe}
& "$root\downloads\7zr.exe" x -y "-o$payload\Backend" "$root\downloads\7zip.exe" 7z.exe 7zG.exe 7zFM.exe 7z.dll License.txt 7-zip.chm 'Lang\*' | Out-Host
CheckExit '7-Zip payload extraction'
Copy-Item src\Engine\SmartZip.ahk "$payload\Engine\SmartZip.ahk" -Force
Copy-Item vendor\AutoHotkey\AutoHotkey64.exe "$payload\Engine" -Force
Copy-Item vendor\AutoHotkey\license.txt "$payload\Licenses\AutoHotkey-GPL2-PCRE.txt" -Force
$up=Get-ChildItem vendor -Directory -Filter 'SmartZip-*' | Select-Object -First 1
Copy-Item (Join-Path $up.FullName LICENSE) "$payload\Licenses\SmartZip-MIT.txt" -Force
Copy-Item "$payload\Backend\License.txt" "$payload\Licenses\7-Zip.txt" -Force
Copy-Item LICENSE,ThirdPartyNotices.md "$payload" -Force
Copy-Item downloads\smartzip.zip,downloads\ahk-source.zip,downloads\7zip-source.tar.xz "$payload\Sources" -Force
Copy-Item src\Engine\SmartZip.ahk "$payload\Sources\SmartZip-Modern.ahk" -Force
Copy-Item README.md "$payload" -Force

if($Signing -eq 'Test'){
  $publisher='CN=SmartZip Modern Evaluation'
  $pfx="$root\.private\test-signing.pfx"; $passFile="$root\.private\test-signing.password.dpapi"
  if(!(Test-Path -LiteralPath $pfx)){
    $password=[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
    $rsa=[Security.Cryptography.RSA]::Create(3072)
    $req=[Security.Cryptography.X509Certificates.CertificateRequest]::new($publisher,$rsa,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $req.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false,$false,0,$true))
    $req.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new([Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature,$true))
    $oids=[Security.Cryptography.OidCollection]::new();$oids.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))|Out-Null
    $req.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids,$true))
    $cert=$req.CreateSelfSigned([DateTimeOffset]::Now.AddMinutes(-5),[DateTimeOffset]::Now.AddYears(2))
    [IO.File]::WriteAllBytes($pfx,$cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx,$password))
    ConvertTo-SecureString $password -AsPlainText -Force | ConvertFrom-SecureString | Set-Content -LiteralPath $passFile
  }else{
    $secure=Get-Content -LiteralPath $passFile | ConvertTo-SecureString
    $password=[Net.NetworkCredential]::new('',$secure).Password
    $cert=[Security.Cryptography.X509Certificates.X509Certificate2]::new($pfx,$password,[Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
  }
  [IO.File]::WriteAllBytes("$payload\Identity.cer",$cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
  $certHash=(Get-FileHash "$payload\Identity.cer" -Algorithm SHA256).Hash
  $testLiteral='true';$testFlag='1'
}else{
  if(!$env:SMARTZIP_SIGN_PFX -or !$env:SMARTZIP_SIGN_PASSWORD -or !$env:SMARTZIP_PUBLISHER){throw 'Release requires SMARTZIP_SIGN_PFX, SMARTZIP_SIGN_PASSWORD and SMARTZIP_PUBLISHER. No test-key fallback.'}
  $pfx=$env:SMARTZIP_SIGN_PFX;$password=$env:SMARTZIP_SIGN_PASSWORD;$publisher=$env:SMARTZIP_PUBLISHER
  $cert=$releaseCert
  [IO.File]::WriteAllBytes("$payload\Identity.cer",$cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
  $certHash=(Get-FileHash "$payload\Identity.cer" -Algorithm SHA256).Hash;$testLiteral='false';$testFlag='0'
}
$xmlPublisher=[Security.SecurityElement]::Escape($publisher)
foreach($pair in @(@('AppxManifest.xml.in',"$root\build\identity\AppxManifest.xml"),@('launcher.manifest.in',"$root\build\launcher.manifest"))){
  (Get-Content "packaging\$($pair[0])" -Raw).Replace('@PUBLISHER@',$xmlPublisher).Replace('@VERSION@',$Version) | Set-Content -LiteralPath $pair[1] -Encoding utf8
}
Copy-Item "$payload\Assets" "$root\build\identity" -Recurse -Force
'1 24 "launcher.manifest"' | Set-Content build\launcher.rc -Encoding ascii
& "$llvm\llvm-windres.exe" -I "$root\build" "$root\build\launcher.rc" -O coff -o "$root\build\launcher.res.o"
CheckExit 'launcher resource'
$common=@('-std=c++17','-O2','-static','-DUNICODE','-D_UNICODE','-D_WIN32_WINNT=0x0A00','-Wl,--dynamicbase','-Wl,--nxcompat')
$beforeFileTime=$cert.NotBefore.ToUniversalTime().ToFileTimeUtc();$afterFileTime=$cert.NotAfter.ToUniversalTime().ToFileTimeUtc()
$certBytes=[IO.File]::ReadAllBytes("$payload\Identity.cer")
@"
// Generated public constants. No PFX/private key material.
static const BYTE EmbeddedCertificate[]={ $($certBytes -join ',') };
static constexpr char CertificateSha256[]="$certHash";
static constexpr wchar_t CertificateSha256W[]=L"$certHash";
static constexpr char CertificateThumbprint[]="$($cert.Thumbprint)";
static constexpr wchar_t CertificateThumbprintW[]=L"$($cert.Thumbprint)";
static constexpr wchar_t CertificateSubject[]=L"$publisher";
static constexpr FILETIME CertificateNotBefore={ $($beforeFileTime -band 4294967295L), $($beforeFileTime -shr 32) };
static constexpr FILETIME CertificateNotAfter={ $($afterFileTime -band 4294967295L), $($afterFileTime -shr 32) };
"@ | Set-Content build\CertificateIdentity.g.h -Encoding utf8
'1 24 "certificate-helper.manifest"'|Set-Content build\certificate-helper.rc -Encoding ascii
& "$llvm\llvm-windres.exe" -I "$root\packaging" build\certificate-helper.rc -O coff -o build\certificate-helper.res.o
CheckExit 'certificate helper manifest'
if($Signing -eq 'Test'){
& "$llvm\x86_64-w64-mingw32-clang++.exe" @common -I build -municode -mwindows src\CertificateTrustHelper.cpp build\certificate-helper.res.o -o "$payload\CertificateTrustHelper.exe" -lcrypt32 -ladvapi32 -lshell32
CheckExit 'native certificate helper'
Sign "$payload\CertificateTrustHelper.exe"
$trustHash=(Get-FileHash "$payload\CertificateTrustHelper.exe").Hash
& "$llvm\x86_64-w64-mingw32-clang++.exe" @common -I build -DCERTIFICATE_SELF_TEST -municode src\CertificateTrustHelper.cpp -o build\tests\CertificateTests.exe -lcrypt32 -ladvapi32 -lshell32
CheckExit 'certificate test build'
& .\build\tests\CertificateTests.exe;CheckExit 'certificate read-only tests'
}else{
  $trustHash=''
  if(Test-Path -LiteralPath "$payload\CertificateTrustHelper.exe"){Remove-Item -LiteralPath "$payload\CertificateTrustHelper.exe"}
}
& "$llvm\x86_64-w64-mingw32-clang++.exe" @common -shared src\ContextMenu.cpp -o "$payload\SmartZipContextMenu.dll" -lole32 -lshell32 -lshlwapi -luuid
CheckExit 'COM DLL'
& "$llvm\x86_64-w64-mingw32-clang++.exe" @common -municode -mwindows src\Launcher.cpp build\launcher.res.o -o "$payload\SmartZip.exe" -lshell32
CheckExit 'launcher'
& "$llvm\x86_64-w64-mingw32-clang++.exe" @common -municode src\NativeTests.cpp -o build\tests\NativeTests.exe -lshell32
CheckExit 'native tests build'
& .\build\tests\NativeTests.exe;CheckExit 'native tests'
& "$llvm\x86_64-w64-mingw32-clang++.exe" @common -municode src\ComTests.cpp -o build\tests\ComTests.exe -lshell32 -lole32 -luuid
CheckExit 'COM tests build'
$fixture=New-Item -ItemType Directory -Force "$root\build\tests\com-fixtures"
foreach($ext in 'zip','rar','7z','001','cab','bz2','gz','gzip','tar','txt'){[IO.File]::WriteAllBytes((Join-Path $fixture.FullName "a.$ext"),[byte[]]@())}
New-Item -ItemType Directory -Force "$($fixture.FullName)\folder","$($fixture.FullName)\folder.zip" | Out-Null
& "$root\build\tests\ComTests.exe" "$payload\SmartZipContextMenu.dll" $fixture.FullName
CheckExit 'standalone COM selection tests (no registration)'
$escaped=$publisher.Replace('\','\\').Replace('"','\"')
@"
// Generated by build.ps1, not a secret.
internal static class ProductIdentity {
 internal const string Name="SmartZip.Modern";
 internal const string Publisher="$escaped";
 internal const string Version="$Version";
 internal static readonly bool TestSigned=$testLiteral;
 internal const string FaultAt="$FaultAt";
 internal const string CertificateSha256="$certHash";
 internal const string CertificateThumbprint="$($cert.Thumbprint)";
 internal const string TrustHelperSha256="$trustHash";
 internal const long NotBeforeTicks=$($cert.NotBefore.ToUniversalTime().Ticks)L;
 internal const long NotAfterTicks=$($cert.NotAfter.ToUniversalTime().Ticks)L;
}
"@ | Set-Content src\DeploymentHelper\ProductIdentity.g.cs -Encoding utf8
dotnet publish src\DeploymentHelper\DeploymentHelper.csproj -c Release -o "$root\build\helper" -p:PublishTrimmed=true -p:TrimMode=link -p:TrimmerSingleWarn=false -p:TreatWarningsAsErrors=true -p:ILLinkTreatWarningsAsErrors=true -p:DebugType=None -p:DebugSymbols=false --nologo
CheckExit 'deployment helper'
dotnet run --project tests\TransactionTests\TransactionTests.csproj -c Release --no-launch-profile
CheckExit 'fault-injected transaction tests (no package/certificate writes)'
dotnet run --project tests\JournalTests\JournalTests.csproj -c Release --no-launch-profile
CheckExit 'source-generated journal tests (reflection disabled)'
dotnet run --project tests\PipeTests\PipeTests.csproj -c Release --no-launch-profile
CheckExit 'real cross-process pipe regression tests (no elevation/certificate/package writes)'
Copy-Item "$root\.tools\inno\tools\license.txt" "$payload\Licenses\InnoSetup.txt" -Force
Copy-Item "$root\.tools\llvm-mingw-20260826-ucrt-x86_64\LICENSE.TXT" "$payload\Licenses\LLVM.txt" -Force
New-Item -ItemType Directory -Force "$payload\Licenses\NativeRuntime" | Out-Null
Copy-Item "$root\.tools\llvm-mingw-20260826-ucrt-x86_64\x86_64-w64-mingw32\share\mingw32\COPYING*" "$payload\Licenses\NativeRuntime" -Force
$nugetRoot = if($env:NUGET_PACKAGES){$env:NUGET_PACKAGES}else{"$env:USERPROFILE\.nuget\packages"}
$runtimeNotices=Get-ChildItem "$nugetRoot\microsoft.netcore.app.runtime.win-x64" -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
Copy-Item "$runtimeNotices\LICENSE.TXT" "$payload\Licenses\DotNet-MIT.txt" -Force
Copy-Item "$runtimeNotices\THIRD-PARTY-NOTICES.TXT" "$payload\Licenses\DotNet-ThirdParty.txt" -Force
if(Test-Path "$root\licenses"){Copy-Item "$root\licenses\*" "$payload\Licenses" -Recurse -Force}
Copy-Item build\helper\DeploymentHelper.exe "$payload" -Force
& "$sdk\makeappx.exe" pack /o /d "$root\build\identity" /nv /p "$payload\Identity.msix"
CheckExit 'identity package'
Sign "$payload\Identity.msix";Sign "$payload\SmartZip.exe";Sign "$payload\SmartZipContextMenu.dll";Sign "$payload\DeploymentHelper.exe"
if($Signing -eq 'Release'){& "$sdk\signtool.exe" verify /pa "$payload\Identity.msix";CheckExit 'production certificate trust'}
$faultSuffix=if($FaultAt){"-fault-$FaultAt"}else{''}
& "$inno" "/DProductVersion=$Version" "/DTestSigned=$testFlag" "/DSetupSuffix=$faultSuffix" installer\SmartZipModern.iss
CheckExit 'single-file installer'
if($Signing -eq 'Test'){
  & "$inno" /O- /Q "/DProductVersion=$Version" /DTestSigned=0 installer\SmartZipModern.iss
  CheckExit 'production wizard syntax only (no production installer emitted)'
}
$setupName=if($Signing -eq 'Test'){"SmartZipSetup-$Version-test$faultSuffix.exe"}else{"SmartZipSetup-$Version-x64.exe"}
Sign "$root\dist\$setupName"
if($Signing -eq 'Release'){& "$sdk\signtool.exe" verify /pa "$root\dist\$setupName";CheckExit 'production installer trust'}
if($Signing -eq 'Test' -and !$FaultAt){& "$root\tests\ReleaseGate.Tests.ps1" -TestInstaller "$root\dist\$setupName" -Version $Version}
Get-Item "dist\$setupName" | Select-Object FullName,Length
Get-FileHash "dist\$setupName" -Algorithm SHA256 | Format-List Hash
Write-Host 'BUILD ONLY. Installer has NOT been executed. No package or certificate was registered.'
