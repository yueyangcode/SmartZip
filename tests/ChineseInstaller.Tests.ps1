$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$path = Join-Path $root 'installer\SmartZipModern.iss'
$bytes = [IO.File]::ReadAllBytes($path)
if ($bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) { throw 'Inno Unicode script must have a UTF-8 BOM.' }
$iss = [IO.File]::ReadAllText($path)
if (!$iss.Contains('MessagesFile: "ChineseSimplified.isl"')) { throw 'Missing Chinese language selection.' }
if ($iss.Contains('compiler:Default.isl')) { throw 'English wizard language unexpectedly enabled.' }
$language = [IO.File]::ReadAllText((Join-Path $root 'installer\ChineseSimplified.isl'))
foreach ($setting in @('DialogFontName=Microsoft YaHei UI', 'DialogFontSize=9', 'WelcomeFontName=Microsoft YaHei UI', 'WelcomeFontSize=12')) {
    if ($language -notmatch ('(?m)^' + [regex]::Escape($setting) + '\r?$')) { throw "Missing shared Chinese Setup/Uninstall font setting: $setting" }
}
if ($iss -match '(?im)^\s*(?:DialogFontName|WelcomeFontName|DefaultDialogFontName)\s*=' -or $iss -match '(?i)\.Font\.Name\s*:=') { throw 'Keep installer fonts in the shared language file, not per-control overrides.' }
if (!$iss.Contains('DisableDirPage=no') -or $iss.Contains('CreateInputDirPage') -or !$iss.Contains('--root')) { throw 'Use the standard final-directory page and pass that root to the deployment helper.' }
if (!$iss.Contains('WizardForm.DirBrowseButton.OnClick := @BrowseInstallDirectory;') -or
    !$iss.Contains('WizardForm.DirEdit.OnExit := @NormalizeDirectory;') -or
    $iss -notmatch '(?s)if CurPageID = wpSelectDir then begin\s+NormalizeDirectory\(nil\);') { throw 'Browse, typed input and Next must share the same path normalization.' }
if ($iss -notmatch "(?s)if DirExists\(WizardForm.DirEdit.Text\) or FileExists\(WizardForm.DirEdit.Text\) then begin\s+EnsurePayload;\s+Result := RunHelper\('preflight'\);\s+if not Result then exit;\s+Upgrading := True;") { throw 'Occupied targets need real identity preflight before being accepted as upgrades.' }
if (!$iss.Contains('if not Upgrading then RemoveFreshInstallMetadata;') -or [regex]::Matches($iss, '\bRemoveFreshInstallMetadata\b').Count -ne 2 -or !$iss.Contains('UninstallLogMode=append') -or !$iss.Contains('SetupMutex=SmartZip.Modern.Setup')) { throw 'Upgrade must preserve old uninstall metadata and exclude concurrent setup.' }
if ($iss -notmatch "(?s)if BrowseForFolder\([^\r\n]+\) then\s+WizardForm.DirEdit.Text := SmartZipDirectory\(Path\);" -or
    !$iss.Contains("CompareText(ExtractFileName(Result), 'SmartZip') <> 0") -or
    !$iss.Contains("if Result = '' then exit;")) { throw 'Only confirmed browsing may change the target; empty and already-suffixed input must be preserved.' }
if (!$iss.Contains("CreateInputOptionPage(wpSelectDir,")) { throw 'Certificate consent must remain after directory selection.' }
$helper = [IO.File]::ReadAllText((Join-Path $root 'src\DeploymentHelper\Program.cs'))
if (!$helper.Contains('MessageBoxW(IntPtr.Zero,UserError(ex)')) { throw 'Raw diagnostic text must not be the user-facing message.' }
if (!$helper.Contains('无需重复安装')) { throw 'Missing actionable already-installed explanation.' }
Write-Host 'PASS Chinese wizard, shared CJK Setup/Uninstall fonts, UTF-8 BOM, localized errors, standard final-path page and browse/type/Next wiring'
