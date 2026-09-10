$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
& (Join-Path $PSScriptRoot 'ChineseInstaller.Tests.ps1')
$installer=[IO.File]::ReadAllText((Join-Path $root 'installer\SmartZipModern.iss'))
$page=[regex]::Match($installer, "(?s)  TrustPage := CreateInputOptionPage\(wpSelectDir,.*?  TrustPage.Add\('[^\r\n]+\);\r?\n").Value
if(!$page){throw 'Cannot find the real production certificate page.'}
$page=$page.Replace('TrustPage','PreviewPage').Replace('wpSelectDir','wpWelcome')
$out=Join-Path $root 'build\tests\font-wizard'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$template=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'FontPreview.iss.in'))
$source=$template.Replace('@OUTPUT@',$out).Replace('@LANGUAGE@',(Join-Path $root 'installer\ChineseSimplified.isl')).Replace('@CONSENT_PAGE@',$page)
if($source -match '(?im)^\[(Files|Registry|Icons|Run|UninstallRun|UninstallDelete)\]' -or $source -match '(?i)\b(Exec|ShellExec|ExtractTemporaryFiles|RegWrite\w*|RegDelete\w*)\s*\('){throw 'Font preview must not deploy or clean up anything.'}
foreach($guard in @('CreateAppDir=no','Uninstallable=no','CreateUninstallRegKey=no','Result := PageID <> PreviewPage.ID;',"Result := 'FONT PREVIEW ONLY. Installation is disabled.';")){
  if(!$source.Contains($guard)){throw "Missing preview safety guard: $guard"}
}
$sourcePath=Join-Path $out 'SmartZip-FontPreview.iss'
[IO.File]::WriteAllText($sourcePath,$source,[Text.UTF8Encoding]::new($true))
& "$root\.tools\inno\tools\ISCC.exe" /Q $sourcePath
if($LASTEXITCODE -ne 0){throw 'Font preview compilation failed.'}
$log=Join-Path $out 'selftest.log'
$test=Start-Process -FilePath (Join-Path $out 'SmartZip-FontPreview.exe') -ArgumentList "/SELFTEST=1 /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG=`"$log`"" -WindowStyle Hidden -Wait -PassThru
if($test.ExitCode -ne 1 -or !([IO.File]::ReadAllText($log).Contains('FONT_PREVIEW_SELFTEST_NO_INSTALL'))){throw 'Preview no-install self-test failed.'}
# Execute the real navigation branch in Inno's Pascal VM. Only replace the
# page object's ID and the window-close side effect with test stand-ins.
$handler=[regex]::Match($source,'(?s)function NextButtonClick\(CurPageID: Integer\): Boolean;.*?\r?\nend;').Value
if(!$handler){throw 'Missing font-preview navigation handler.'}
$handler=$handler.Replace('PreviewPage.ID','101').Replace('WizardForm.Close','Closed := True')
$navigation=@'
[Setup]
AppName=SmartZip Font Navigation Tests
AppVersion=1
DefaultDirName={tmp}\SmartZip-Font-Navigation-NoInstall
CreateAppDir=no
Uninstallable=no
CreateUninstallRegKey=no
PrivilegesRequired=lowest
OutputDir=.
OutputBaseFilename=FontNavigationTests
[Code]
var Closed: Boolean;
@HANDLER@
function InitializeSetup: Boolean;
begin
  Closed := False;
  if not NextButtonClick(wpWelcome) or Closed then RaiseException('Hidden welcome page must advance without closing.');
  if not NextButtonClick(wpLicense) or Closed then RaiseException('Pre-preview navigation must be allowed.');
  if NextButtonClick(101) or not Closed then RaiseException('Preview Next must close, not enter installation.');
  Log('FONT_PREVIEW_NAVIGATION_3_CASES_NO_INSTALL');
  Result := False;
end;
'@
$navSource=Join-Path $out 'FontNavigationTests.iss'
[IO.File]::WriteAllText($navSource,$navigation.Replace('@HANDLER@',$handler),[Text.UTF8Encoding]::new($true))
& "$root\.tools\inno\tools\ISCC.exe" /Q $navSource
if($LASTEXITCODE -ne 0){throw 'Navigation test compilation failed.'}
$navLog=Join-Path $out 'navigation-selftest.log'
$navTest=Start-Process -FilePath (Join-Path $out 'FontNavigationTests.exe') -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG=`"$navLog`"" -WindowStyle Hidden -Wait -PassThru
if($navTest.ExitCode -ne 1 -or !([IO.File]::ReadAllText($navLog).Contains('FONT_PREVIEW_NAVIGATION_3_CASES_NO_INSTALL'))){throw 'Actual preview navigation regression failed.'}
'PASS: production consent page/shared CJK configuration, no-install guards, and 3 real Pascal navigation cases. Visual glyph/layout acceptance still needs the target machine.'
