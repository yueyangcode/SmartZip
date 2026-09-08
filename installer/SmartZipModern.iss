#ifndef ProductVersion
 #define ProductVersion "0.1.0.8"
#endif
#define Root SourcePath + "..\"
[Setup]
AppId={{DA975784-DC84-48EF-9A47-F60C0C969280}
AppName=SmartZip
AppVersion={#ProductVersion}
AppVerName=SmartZip {#ProductVersion} (本机开发测试版)
AppPublisher=SmartZip
DefaultDirName={localappdata}\Programs\SmartZip
DisableDirPage=no
UsePreviousAppDir=no
DefaultGroupName=SmartZip
DisableProgramGroupPage=yes
UsePreviousGroup=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0.22621
OutputDir={#Root}dist
OutputBaseFilename=SmartZipSetup-test9-dirfix2
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#Root}build\payload\Assets\SmartZip.ico
UninstallDisplayIcon={app}\Versions\{#ProductVersion}\Assets\SmartZip.ico
LicenseFile={#Root}LICENSE
CloseApplications=no
RestartApplications=no
VersionInfoVersion={#ProductVersion}
VersionInfoDescription=SmartZip local-development test9 directory fix

[Languages]
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"

[Messages]
SelectDirBrowseLabel=点击“浏览”选择父目录，确认后会自动添加 SmartZip 文件夹。下方显示最终安装位置；选择已有的 SmartZip 文件夹不会重复添加。请选择当前用户可写的本地 NTFS 磁盘。

[Files]
; Payload is staged and validated during PrepareToInstall, before Inno commits
; its own uninstall record and shortcuts. dontcopy prevents a second overwrite.
Source: "{#Root}build\payload\*"; DestDir: "{tmp}\payload"; Flags: dontcopy recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\SmartZip\SmartZip 设置"; Filename: "{app}\Versions\{#ProductVersion}\SmartZip.exe"
Name: "{userprograms}\SmartZip\卸载 SmartZip"; Filename: "{uninstallexe}"

[Icons]
Name: "{userprograms}\SmartZip\检查更新"; Filename: "{app}\Versions\{#ProductVersion}\SmartZip.exe"; Parameters: "--check-updates"

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
  Result := Exec(Helper, Operation + ' --root "' + ExpandConstant('{app}') + '"', '', SW_HIDE, ewWaitUntilTerminated, Code);
  if Result then Result := Code = 0;
end;

function SmartZipDirectory(Path: String): String;
begin
  Result := RemoveBackslashUnlessRoot(Trim(Path));
  if Result = '' then exit;
  if CompareText(ExtractFileName(Result), 'SmartZip') <> 0 then
    Result := AddBackslash(Result) + 'SmartZip';
end;

procedure NormalizeDirectory(Sender: TObject);
begin
  WizardForm.DirEdit.Text := SmartZipDirectory(WizardForm.DirEdit.Text);
end;

procedure BrowseInstallDirectory(Sender: TObject);
var Path: String;
begin
  Path := WizardForm.DirEdit.Text;
  // Inno 6.2.2 AppendDefaultDirName blindly appends even to an existing SmartZip.
  // Reuse its native folder picker, then normalize once for both input methods.
  if CompareText(ExtractFileName(RemoveBackslashUnlessRoot(Path)), 'SmartZip') = 0 then
    Path := ExtractFileDir(RemoveBackslashUnlessRoot(Path));
  if BrowseForFolder('选择父目录（将自动添加 SmartZip 文件夹），也可以直接选择已有的 SmartZip 文件夹。', Path, False) then
    WizardForm.DirEdit.Text := SmartZipDirectory(Path);
end;

procedure InitializeWizard;
begin
  WizardForm.DirBrowseButton.OnClick := @BrowseInstallDirectory;
  WizardForm.DirEdit.OnExit := @NormalizeDirectory;
  TrustPage := CreateInputOptionPage(wpSelectDir, '开发测试证书',
    '软件仅为当前登录用户安装。',
    '此测试版会将项目公钥证书添加到“本地计算机 → 受信任人”，不会添加到根证书库，也不会导入私钥。证书助手可能请求管理员权限；系统已关闭 UAC 时可能不弹窗，安装器不会更改 UAC。软件仅为当前用户注册。安装前已存在的证书不会被卸载器擅自删除。', False, False);
  TrustPage.Add('我同意添加此项目专用测试证书，并允许证书助手请求管理员权限。');
  TrustPage.Values[0] := False;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = wpSelectDir then begin
    NormalizeDirectory(nil);
    if DirExists(WizardForm.DirEdit.Text) or FileExists(WizardForm.DirEdit.Text) then begin
      MsgBox('安装目录已存在：' + #13#10 + WizardForm.DirEdit.Text + #13#10#13#10 +
        '为保护原有文件，此测试版不会覆盖该目录。请选择其他父目录，例如使用默认安装位置。不要删除原 SmartZip 文件夹。', mbInformation, MB_OK);
      Result := False;
      exit;
    end;
  end;
  if (CurPageID = TrustPage.ID) and not TrustPage.Values[0] then begin
    MsgBox('请先勾选同意添加项目专用测试证书，再继续安装。', mbInformation, MB_OK);
    Result := False;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if Prepared then exit;
  if TriedPrepare then begin Result := '上一次安装尝试失败。请关闭安装程序，查看日志后再重试。'; exit; end;
  if not TrustPage.Values[0] then begin Result := '此测试版需要手动确认测试证书，不支持静默安装。'; exit; end;
  TriedPrepare := True;
  ExtractTemporaryFiles('{tmp}\payload\*');
  if not RunHelper('preflight') then begin Result := '安装前检查未通过，本次安装尚未提交。请查看错误提示和日志。'; exit; end;
  Prepared := RunHelper('prepare');
  if not Prepared then Result := '部署失败，程序已尝试回滚。请查看错误提示和日志确认清理结果。本次尚未提交卸载入口或开始菜单快捷方式。';
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    if not RunHelper('commit') then RaiseException('安装提交校验失败，退出时将尝试回滚。请保留日志。');
  end;
  if CurStep = ssDone then Completed := True;
end;

procedure DeinitializeSetup;
begin
  if Prepared and not Completed then begin
    if RunHelper('rollback') then begin
      RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{DA975784-DC84-48EF-9A47-F60C0C969280}_is1');
      DeleteFile(ExpandConstant('{userprograms}\SmartZip\SmartZip 设置.lnk'));
      DeleteFile(ExpandConstant('{userprograms}\SmartZip\卸载 SmartZip.lnk'));
      DeleteFile(ExpandConstant('{userprograms}\SmartZip\检查更新.lnk'));
      RemoveDir(ExpandConstant('{userprograms}\SmartZip'));
    end else begin
      RollbackFailed := True;
      MsgBox('回滚未完成，程序已停止删除文件。请保留错误日志并联系开发者检查；本次安装未成功。', mbError, MB_OK);
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
    MsgBox('安装包身份或证书清理失败，或管理员授权被取消。已保留文件和卸载入口；部分部署状态可能已经变化，请查看日志后再重试。', mbError, MB_OK);
    Abort;
  end;
  Log('Deployment cleanup succeeded; allowing Inno to remove product files and uninstall metadata.');
end;
