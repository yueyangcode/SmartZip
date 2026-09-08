param([Parameter(Mandatory)][string]$Installer,[Parameter(Mandatory)][string]$Version)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
if($Version -notmatch '^\d+\.\d+\.\d+\.\d+$'){throw 'Use the exact four-part product version.'}
$file=Get-Item -LiteralPath $Installer
if($file.Name -ne "SmartZipSetup-$Version-x64.exe" -or $file.VersionInfo.ProductVersion.Trim() -ne $Version){throw 'A matching production installer is required, not a test/fault build.'}
$signature=Get-AuthenticodeSignature -LiteralPath $file.FullName
if($signature.Status -ne 'Valid' -or !$signature.SignerCertificate -or $signature.SignerCertificate.Subject -eq $signature.SignerCertificate.Issuer -or $signature.SignerCertificate.Subject -eq 'CN=SmartZip Modern Evaluation'){throw 'WinGet generation blocked: valid publicly trusted production signing is required.'}
$hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
$url="https://github.com/yueyangcode/SmartZip/releases/download/v$Version/$($file.Name)"
$out=Join-Path $root "build\winget\manifests\y\yueyangcode\SmartZip\$Version"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$manifest=@"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.singleton.1.6.0.schema.json
PackageIdentifier: yueyangcode.SmartZip
PackageVersion: $Version
PackageLocale: zh-CN
Publisher: SmartZip
PublisherUrl: https://github.com/yueyangcode
PackageName: SmartZip
PackageUrl: https://github.com/yueyangcode/SmartZip
License: MIT; bundled components retain their own licenses
LicenseUrl: https://github.com/yueyangcode/SmartZip/blob/main/ThirdPartyNotices.md
ShortDescription: Windows 11 现代右键菜单智能解压工具
MinimumOSVersion: 10.0.22621.0
InstallerType: inno
Scope: user
UpgradeBehavior: install
InstallModes:
  - interactive
  - silent
  - silentWithProgress
InstallerSwitches:
  Silent: /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-
  SilentWithProgress: /SILENT /SUPPRESSMSGBOXES /NORESTART /SP-
  InstallLocation: /DIR="<INSTALLPATH>"
Installers:
  - Architecture: x64
    InstallerUrl: $url
    InstallerSha256: $hash
    ProductCode: '{DA975784-DC84-48EF-9A47-F60C0C969280}_is1'
ManifestType: singleton
ManifestVersion: 1.6.0
"@
[IO.File]::WriteAllText((Join-Path $out 'yueyangcode.SmartZip.yaml'),$manifest,[Text.UTF8Encoding]::new($false))
Write-Output "Generated: $out"
Write-Output 'NOT SUBMITTED: publish the exact stable release asset, verify its downloaded SHA-256, run winget validate and clean-machine silent install/upgrade/uninstall before submitting.'
