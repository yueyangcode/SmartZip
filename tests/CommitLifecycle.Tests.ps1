$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$installer = [IO.File]::ReadAllText((Join-Path $root 'installer\SmartZipModern.iss'))
# Execute production event handlers with the actual Inno 6.2.2 lifecycle.
# Only deployment and fresh-install cleanup are stand-ins: no product/package/
# certificate/registry/file payload is installed by this test executable.
$handlers = [regex]::Match($installer, '(?s)procedure RollbackDeployment;.*?(?=procedure CurUninstallStepChanged)').Value
if (!$handlers) { throw 'Missing production installation lifecycle.' }
# Wrap, rather than use an event attribute: Inno runs attributed handlers before
# the main handler, which would sample the heading before production updates it.
$handlers = $handlers.Replace('procedure CurPageChanged(CurPageID: Integer);', 'procedure ProductionPageChanged(CurPageID: Integer);')
$variables = [regex]::Match($installer, '(?m)^  Prepared,.*?: Boolean;').Value
if (!$variables) { throw 'Missing production lifecycle variables.' }
$out = Join-Path $root 'build\tests\commit-lifecycle'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$template = @'
[Setup]
AppId=SmartZip.NoInstall.CommitLifecycleTests
AppName=SmartZip No-Payload Commit Lifecycle Tests
AppVersion=1
DefaultDirName={tmp}\SmartZip-NoInstall
CreateAppDir=no
Uninstallable=no
CreateUninstallRegKey=no
UsePreviousAppDir=no
UsePreviousGroup=no
UsePreviousTasks=no
PrivilegesRequired=lowest
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
CloseApplications=no
RestartApplications=no
OutputDir=.
OutputBaseFilename=CommitLifecycleTests
[Code]
var
@VARIABLES@
  Scenario: String;
function RunHelper(Operation: String): Boolean;
begin
  Log('TEST_HELPER=' + Operation);
  Result := True;
  if Operation = 'commit' then begin
    if Scenario = 'commit-exception' then RaiseException('Simulated helper launch exception');
    Result := (Scenario = 'success') or (Scenario = 'finalize-failure');
  end;
  if Operation = 'rollback' then begin
    if Scenario = 'rollback-exception' then RaiseException('Simulated rollback exception');
    Result := Scenario <> 'rollback-failure';
  end;
  if Operation = 'finalize' then Result := Scenario <> 'finalize-failure';
end;
procedure RemoveFreshInstallMetadata;
begin
  Log('TEST_FRESH_METADATA_CLEANUP');
  if Scenario = 'fresh-cleanup-failure' then RaiseException('Simulated metadata cleanup failure');
end;
@HANDLERS@
function InitializeSetup: Boolean;
begin
  Scenario := ExpandConstant('{param:CASE|success}');
  Log('TEST_CASE=' + Scenario);
  Result := True;
end;
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Prepared := True;
  Upgrading := (Scenario <> 'fresh-failure') and (Scenario <> 'fresh-cleanup-failure');
  Result := '';
end;
procedure CurPageChanged(CurPageID: Integer);
begin
  ProductionPageChanged(CurPageID);
  if CurPageID = wpFinished then begin
    Log('TEST_FINISHED_COMPLETED=' + IntToStr(Ord(Completed)));
    Log('TEST_FINISHED_HEADING=' + WizardForm.FinishedHeadingLabel.Caption);
    Log('TEST_FINISHED_TEXT=' + WizardForm.FinishedLabel.Caption);
  end;
end;
<event('DeinitializeSetup')>
procedure RecordShutdown;
begin
  Log('TEST_DEINIT_COMPLETED=' + IntToStr(Ord(Completed)));
  Log('TEST_DEINIT_ROLLBACK_FAILED=' + IntToStr(Ord(RollbackFailed)));
end;
'@
$source = $template.Replace('@VARIABLES@', $variables).Replace('@HANDLERS@', $handlers)
if ($source -match '(?im)^\[(Files|Registry|Icons|Run|UninstallRun|UninstallDelete)\]' -or $source -match '(?i)\b(Exec|ShellExec|RegDelete\w*|DeleteFile|RemoveDir)\s*\(') { throw 'Lifecycle tests must not perform real deployment or cleanup.' }
$path = Join-Path $out 'CommitLifecycleTests.iss'
[IO.File]::WriteAllText($path, $source, [Text.UTF8Encoding]::new($true))
& "$root\.tools\inno\tools\ISCC.exe" /Q $path
if ($LASTEXITCODE -ne 0) { throw 'Lifecycle test compilation failed.' }
$cases = [ordered]@{ success=0; 'commit-failure'=20; 'commit-exception'=20; 'rollback-failure'=21; 'rollback-exception'=21; 'fresh-failure'=20; 'fresh-cleanup-failure'=21; 'finalize-failure'=0 }
foreach ($case in $cases.Keys) {
    $log = Join-Path $out "$case.log"
    $test = Start-Process -FilePath (Join-Path $out 'CommitLifecycleTests.exe') -ArgumentList "/CASE=$case /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG=`"$log`"" -WindowStyle Hidden -PassThru
    if (!$test.WaitForExit(30000)) { throw "Lifecycle test timed out; left running: $case" }
    $text = [IO.File]::ReadAllText($log)
    $success = $cases[$case] -eq 0
    if ($test.ExitCode -ne $cases[$case]) { throw "Wrong exit code for ${case}: $($test.ExitCode), expected $($cases[$case])" }
    if ([regex]::Matches($text, 'TEST_HELPER=commit').Count -ne 1 -or [regex]::Matches($text, 'TEST_HELPER=rollback').Count -ne [int](!$success) -or [regex]::Matches($text, 'TEST_HELPER=finalize').Count -ne [int]$success) { throw "Wrong helper order/counts for $case" }
    if (!$text.Contains('TEST_DEINIT_COMPLETED=' + [int]$success) -or !$text.Contains('TEST_DEINIT_ROLLBACK_FAILED=' + [int]($cases[$case] -eq 21))) { throw "Wrong shutdown state for $case" }
    if (!$success -and !$text.Contains('TEST_FINISHED_HEADING=SmartZip 安装未完成')) { throw "False success heading for $case" }
    if ($text.Contains('TEST_FRESH_METADATA_CLEANUP') -ne $case.StartsWith('fresh-')) { throw "Wrong fresh-only cleanup dispatch for $case" }
    Write-Host "PASS actual Inno lifecycle: $case -> exit $($test.ExitCode), no payload installed."
}
