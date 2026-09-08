[Setup]
; Match test8's current-user context and default target. Never enter installation.
AppId={{DA975784-DC84-48EF-9A47-F60C0C969280}
AppName=SmartZip Modern
AppVersion=0.1.0.7
AppVerName=SmartZip test8 检查诊断（不安装）
DefaultDirName={localappdata}\Programs\SmartZip Modern
DisableDirPage=yes
UsePreviousAppDir=no
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0.22621
OutputDir=..\dist
OutputBaseFilename=SmartZip-Preflight-Diagnostic
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
LicenseFile=..\LICENSE
CloseApplications=no
RestartApplications=no
Uninstallable=no
CreateUninstallRegKey=no
VersionInfoDescription=SmartZip 只读安装前检查诊断

[Languages]
Name: "chinesesimplified"; MessagesFile: "..\installer\ChineseSimplified.isl"

[Messages]
ButtonInstall=开始诊断(&I)
ReadyLabel1=即将检查 test8 的安装前判断条件，不会安装软件或修改系统配置。

[Files]
Source: "..\build\preflight-diagnostic\payload\*"; DestDir: "{tmp}\payload"; Flags: dontcopy recursesubdirs createallsubdirs

[Code]
var Attempted: Boolean; InfoPage: TOutputMsgWizardPage;

procedure InitializeWizard;
begin
  InfoPage := CreateOutputMsgPage(wpLicense, '只读诊断，不执行安装', '用于定位为何 test8 提示已有安装。',
    '只记录本项目目录、注册表、Package 和进程身份。不会导入证书、修改注册表、注册或移除 Package，也不会创建程序安装目录。唯一写入是临时解包文件和诊断日志。诊断完成后会主动停止，这是预期行为。');
end;

procedure Snapshot(LabelText: String);
var S, Path: String;
begin
  Path := ExpandConstant('{localappdata}\Temp\SmartZip-Preflight-Inno-' + ExtractFileName(ExpandConstant('{tmp}')) + '.log');
  S := LabelText + #13#10 + 'App=' + ExpandConstant('{app}') + #13#10 + 'LocalAppData=' + ExpandConstant('{localappdata}') + #13#10 +
    'DirectoryExists=' + IntToStr(Ord(DirExists(ExpandConstant('{app}')))) + #13#10 +
    'ProductKeyExists=' + IntToStr(Ord(RegKeyExists(HKCU, 'Software\SmartZipModern'))) + #13#10 +
    'UninstallKeyExists=' + IntToStr(Ord(RegKeyExists(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{DA975784-DC84-48EF-9A47-F60C0C969280}_is1'))) + #13#10;
  SaveStringToFile(Path, S, True);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Code: Integer; Arguments: String; Started: Boolean;
begin
  Result := '诊断结束，未执行安装。请关闭此程序，将 SmartZip-Preflight 日志交给开发者。';
  if Attempted then exit;
  Attempted := True;
  Snapshot('BEFORE_HELPER');
  ExtractTemporaryFiles('{tmp}\payload\*');
  Arguments := 'preflight';
  if WizardSilent then Arguments := Arguments + ' --no-ui';
  Started := Exec(ExpandConstant('{tmp}\payload\DeploymentHelper.exe'), Arguments, '', SW_HIDE, ewWaitUntilTerminated, Code);
  Snapshot('AFTER_HELPER');
  if not Started then Result := '诊断助手未能启动，未执行安装。'
  else if Code <> 0 then Result := '部分诊断查询失败，请查看日志。未执行安装。';
  // ALWAYS nonempty: Inno must never proceed to directory/registry/file installation.
end;
