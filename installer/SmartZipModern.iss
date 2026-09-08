#ifndef ProductVersion
 #define ProductVersion "0.1.0.5"
#endif
#define Root SourcePath + "..\"
[Setup]
AppId={{DA975784-DC84-48EF-9A47-F60C0C969280}
AppName=SmartZip Modern
AppVersion={#ProductVersion}
AppVerName=SmartZip Modern {#ProductVersion} (LOCAL DEVELOPMENT TEST6)
AppPublisher=SmartZip Modern
DefaultDirName={localappdata}\Programs\SmartZip Modern
DisableDirPage=yes
UsePreviousAppDir=no
DefaultGroupName=SmartZip Modern
DisableProgramGroupPage=yes
UsePreviousGroup=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0.22621
OutputDir={#Root}dist
OutputBaseFilename=SmartZipModernSetup-test6
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#Root}build\payload\Assets\SmartZip.ico
UninstallDisplayIcon={app}\Versions\{#ProductVersion}\Assets\SmartZip.ico
LicenseFile={#Root}LICENSE
CloseApplications=no
RestartApplications=no
VersionInfoVersion={#ProductVersion}
VersionInfoDescription=SmartZip Modern local-development test6

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Payload is staged and validated during PrepareToInstall, before Inno commits
; its own uninstall record and shortcuts. dontcopy prevents a second overwrite.
Source: "{#Root}build\payload\*"; DestDir: "{tmp}\payload"; Flags: dontcopy recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\SmartZip Modern\SmartZip Modern settings"; Filename: "{app}\Versions\{#ProductVersion}\SmartZip.exe"
Name: "{userprograms}\SmartZip Modern\Uninstall SmartZip Modern"; Filename: "{uninstallexe}"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\Versions\{#ProductVersion}"
Type: files; Name: "{app}\.install-transaction"
Type: dirifempty; Name: "{app}\Versions"
Type: dirifempty; Name: "{app}"

[Code]
var
  TrustPage: TInputOptionWizardPage;
  Prepared, Completed, RollbackFailed, TriedPrepare: Boolean;

function Helper: String;
begin
  Result := ExpandConstant('{tmp}\payload\DeploymentHelper.exe');
end;

function RunHelper(Operation: String): Boolean;
var Code: Integer;
begin
  Result := Exec(Helper, Operation, '', SW_HIDE, ewWaitUntilTerminated, Code);
  if Result then Result := Code = 0;
end;

procedure InitializeWizard;
begin
  TrustPage := CreateInputOptionPage(wpLicense, 'Local development certificate',
    'Files and package registration belong to the verified desktop user.',
    'This TEST6 build trusts only its embedded public certificate in Local Machine / Trusted People. Never Root or private keys. The separate certificate helper requests elevation when needed; if UAC is already disabled, no prompt may appear. Setup does not change UAC. A same-user unsplit administrator token is accepted only when UAC is disabled. Pre-existing certificates are not adopted for deletion.', False, False);
  TrustPage.Add('I agree to the dedicated machine-level test certificate and its UAC prompt.');
  TrustPage.Values[0] := False;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = TrustPage.ID) and not TrustPage.Values[0] then begin
    MsgBox('Explicit consent is required for this development-only certificate.', mbInformation, MB_OK);
    Result := False;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if Prepared then exit;
  if TriedPrepare then begin Result := 'The previous attempt failed. Close Setup and review its log before retrying.'; exit; end;
  if not TrustPage.Values[0] then begin Result := 'Interactive certificate consent is required. Silent test installs are not supported.'; exit; end;
  if CompareText(ExpandConstant('{app}'), ExpandConstant('{localappdata}\Programs\SmartZip Modern')) <> 0 then begin
    Result := 'This test build uses its fixed current-user installation directory.'; exit;
  end;
  TriedPrepare := True;
  ExtractTemporaryFiles('{tmp}\payload\*');
  if not RunHelper('preflight') then begin Result := 'Preflight failed. No installation was committed.'; exit; end;
  Prepared := RunHelper('prepare');
  if not Prepared then Result := 'Deployment failed and rollback was attempted. See the helper error/log for its verified result. No uninstall entry or Start menu item has been committed.';
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    if not RunHelper('commit') then RaiseException('Commit validation failed. Setup will roll back on exit.');
  end;
  if CurStep = ssDone then Completed := True;
end;

procedure DeinitializeSetup;
begin
  if Prepared and not Completed then begin
    if RunHelper('rollback') then begin
      RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{DA975784-DC84-48EF-9A47-F60C0C969280}_is1');
      DeleteFile(ExpandConstant('{userprograms}\SmartZip Modern\SmartZip Modern settings.lnk'));
      DeleteFile(ExpandConstant('{userprograms}\SmartZip Modern\Uninstall SmartZip Modern.lnk'));
      RemoveDir(ExpandConstant('{userprograms}\SmartZip Modern'));
    end else begin
      RollbackFailed := True;
      MsgBox('Rollback could not be completed. No further files will be deleted. Preserve the error log and retry project cleanup; do not treat this installation as successful.', mbError, MB_OK);
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var Code: Integer; CleanupSucceeded: Boolean;
begin
  if CurUninstallStep <> usUninstall then exit;
  // Inno 6.2.2 calls usUninstall AFTER confirmation and BEFORE PerformUninstall.
  // Abort here is fatal; a message or a failed Exec alone would not stop deletion.
  Log('Starting package/certificate cleanup after the uninstall confirmation stage.');
  CleanupSucceeded := Exec(ExpandConstant('{app}\Versions\{#ProductVersion}\DeploymentHelper.exe'), 'uninstall', '', SW_HIDE, ewWaitUntilTerminated, Code);
  if CleanupSucceeded then CleanupSucceeded := Code = 0;
  if not CleanupSucceeded then begin
    Log(Format('Deployment cleanup failed (%d); aborting before Inno file/shortcut/uninstall-entry deletion.', [Code]));
    MsgBox('Package/certificate cleanup failed or UAC was cancelled. Files and the uninstall entry were retained. Some deployment state may already have changed; review the deployment log before retrying.', mbError, MB_OK);
    Abort;
  end;
  Log('Deployment cleanup succeeded; allowing Inno to remove product files and uninstall metadata.');
end;
