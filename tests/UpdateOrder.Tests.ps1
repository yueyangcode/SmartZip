$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $root 'src\DeploymentHelper\UpdateCheck.cs'))
$iss=[IO.File]::ReadAllText((Join-Path $root 'installer\SmartZipModern.iss'))
if($source -notmatch '(?s)UpdateDialog.Ask.+?if\(choice!=UpdateDialog.Install\)return;.+?UpdateDialog.Run'){throw 'Consent must precede any update download/install operation.'}
if($source -notmatch '(?s)FileAccess.Read,FileShare.Read.+?UpdateSignature.Verify.+?WaitForIdle.+?revalidate\(\);operation.BeginInstall\(\);.+?Process.Start.+?WaitForExitAsync\(\).+?verifyInstalled'){throw 'Verified file pin, activity gate, revalidation and installer result verification order changed.'}
if($source.Contains('Process.Kill') -or $source.Contains('Verb="runas"') -or !$source.Contains(':Zone.Identifier')){throw 'Do not bypass application lifetime, permission or Internet-zone checks.'}
$prepare=[regex]::Match($iss,'(?s)function PrepareToInstall.+?(?=procedure CurStepChanged)').Value
if($prepare -notmatch "(?s)RunHelper\('preflight'\).+?Upgrading := RegQueryStringValue.+?if not Upgrading and not TrustPage.Values\[0\].+?RunHelper\('prepare'\)"){throw 'Silent upgrade classification must follow read-only identity preflight and precede trust consent/deployment.'}
Write-Host 'PASS source safety order: explicit consent, pinned verification, idle gate, no forced process/elevation, post-install verification; silent upgrade independent of directory-page navigation.'
