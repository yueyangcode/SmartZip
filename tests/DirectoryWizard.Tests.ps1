$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$iss = [IO.File]::ReadAllText((Join-Path $root 'installer\SmartZipModern.iss'))
# Execute the actual production Pascal function with Inno's script VM, not a port.
$function = [regex]::Match($iss, '(?s)function SmartZipDirectory\(Path: String\): String;.*?\r?\nend;').Value
if (!$function) { throw 'Missing production directory function.' }
$out = Join-Path $root 'build\tests\directory-wizard'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$script = @'
[Setup]
AppName=SmartZip Directory Function Test
AppVersion=1
DefaultDirName={tmp}\SmartZip-NoInstall
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=lowest
OutputDir=.
OutputBaseFilename=DirectoryFunctionTests
[Code]
__FUNCTION__
procedure Check(Input, Expected: String);
begin
  if SmartZipDirectory(Input) <> Expected then RaiseException('Path regression: ' + Input);
  if SmartZipDirectory(Expected) <> Expected then RaiseException('Repeated suffix regression: ' + Expected);
end;
function InitializeSetup: Boolean;
begin
  Check('D:\SoftWare', 'D:\SoftWare\SmartZip');
  Check('D:\SoftWare\', 'D:\SoftWare\SmartZip');
  Check('D:\SoftWare\SmartZip', 'D:\SoftWare\SmartZip');
  Check('D:\SoftWare\SmartZip\', 'D:\SoftWare\SmartZip');
  Check('D:\SoftWare\smartzip', 'D:\SoftWare\smartzip');
  Check('D:\SoftWare\SmartZipTools', 'D:\SoftWare\SmartZipTools\SmartZip');
  Check('D:\', 'D:\SmartZip');
  Check('C:\测试 空格 & (目录)', 'C:\测试 空格 & (目录)\SmartZip');
  Check('  D:\SoftWare  ', 'D:\SoftWare\SmartZip');
  Check('', '');
  Log('PASS_DIRECTORY_FUNCTION_10_CASES_NO_INSTALL');
  // Stop before InitializeWizard, PrepareToInstall or installation can run.
  Result := False;
end;
'@
$sourcePath = Join-Path $out 'DirectoryFunctionTests.iss'
[IO.File]::WriteAllText($sourcePath, $script.Replace('__FUNCTION__', $function), [Text.UTF8Encoding]::new($true))
& "$root\.tools\inno\tools\ISCC.exe" /Q $sourcePath
if ($LASTEXITCODE -ne 0) { throw 'Directory test compilation failed.' }
$log = Join-Path $out 'DirectoryFunctionTests.log'
$test = Start-Process -FilePath (Join-Path $out 'DirectoryFunctionTests.exe') -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG=`"$log`"" -WindowStyle Hidden -Wait -PassThru
if ($test.ExitCode -ne 1 -or !([IO.File]::ReadAllText($log).Contains('PASS_DIRECTORY_FUNCTION_10_CASES_NO_INSTALL'))) { throw 'Directory function tests failed.' }
Write-Host 'PASS production Pascal: 10 directory cases and idempotence; InitializeSetup returned false, no installation.'
