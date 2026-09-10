$ErrorActionPreference='Stop'
if ($env:USERNAME -eq 'WDAGUtilityAccount') { throw 'Run source checks on the build host only.' }
$path=Join-Path $PSScriptRoot 'Run-Icon-Upgrade.ps1'
$source=[IO.File]::ReadAllText($path)
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$allowed=@('Get-CimInstance','Join-Path','Get-FileHash','Get-Content','ConvertFrom-Json','Test-Path','Get-Item',
    'Get-ChildItem','Where-Object','Sort-Object','ForEach-Object','Get-ItemProperty','Select-Object','FileTree',
    'Get-AppxPackage','Get-AppxPackageManifest','Get-Process','Snapshot','Healthy','New-Item','Out-Null',
    'ConvertTo-Json','Set-Content','Start-Process','Write-Output')
foreach ($command in $ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true)) {
    if ($command.GetCommandName() -notin $allowed) { throw "Unexpected command: $command" }
}
foreach ($forbidden in @('Add-AppxPackage','Remove-AppxPackage','Import-Certificate','Remove-Item','Stop-Process',
    'Set-ExecutionPolicy','CreateSubKey','SetValue(', 'File]::Delete','File]::Move','-Verb RunAs','/SILENT','/VERYSILENT')) {
    if ($source.Contains($forbidden)) { throw "Unexpected operation: $forbidden" }
}
if ([regex]::Matches($source,'\bStart-Process\b').Count -ne 1 -or
    !$source.Contains("`$installer = 'C:\SmartZipTestInput\SmartZipSetup-0.1.0.15-test.exe'") -or
    !$source.Contains('1AED980A38A21BFC5BC3C92410C5895A2B852F6E2680454AEAECDA9D5F815E2D') -or
    !$source.Contains('4F49B30E7536E0AFE4596593199228C54F04F9C0E35AA781D351253A7F7211B2') -or
    !$source.Contains("`$root = 'C:\SmartZip'") -or !$source.Contains("Healthy `$before '0.1.0.14'") -or
    !$source.Contains('Start-Process -FilePath $installer -ArgumentList') -or
    !$source.Contains('-WindowStyle Normal -PassThru -Wait') -or !$source.Contains('Evidence already exists. No automatic retry.')) {
    throw 'Fixed interactive upgrade and evidence safety guards missing.'
}
$healthy=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Healthy'},$true))
if ($healthy.Count -ne 1) { throw 'Missing actual baseline predicate.' }
. ([scriptblock]::Create($healthy[0].Extent.Text))
$root='C:\SmartZip'; $thumb='A1709CED9DB02150E2FB40CE6496BD1938D89195'
function Fixture {
    @{State=@{Version='0.1.0.14';VersionPath='C:\SmartZip\Versions\0.1.0.14';Publisher='CN=SmartZip Modern Evaluation';
        UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;CertificateThumbprint=$thumb};
      Uninstall=@{DisplayVersion='0.1.0.14';InstallLocation='C:\SmartZip\'};
      Packages=@(@{Version='0.1.0.14';Status='Ok';Publisher='CN=SmartZip Modern Evaluation';PackagedComClassExists=$true});
      Files=@(@{Path='Versions\0.1.0.14\SmartZip.exe'})}
}
if (!(Healthy (Fixture) '0.1.0.14')) { throw 'Correct custom-directory baseline rejected.' }
foreach ($mutation in @(
    {param($s) $s.State.Version='0.1.0.15'}, {param($s) $s.State.VersionPath='C:\Other\Versions\0.1.0.14'},
    {param($s) $s.State.UserSid='wrong-user'}, {param($s) $s.State.CertificateThumbprint='wrong-certificate'},
    {param($s) $s.Uninstall.InstallLocation='C:\Other'}, {param($s) $s.Packages[0].Status='NeedsRemediation'},
    {param($s) $s.Packages[0].PackagedComClassExists=$false}, {param($s) $s.Packages=@()}, {param($s) $s.Files=@()}
)) { $s=Fixture; & $mutation $s; if (Healthy $s '0.1.0.14') { throw 'Unsafe baseline accepted.' } }
$result=& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command "& ([scriptblock]::Create([IO.File]::ReadAllText('$path')))" 2>&1 | Out-String
if ($LASTEXITCODE -ne 1 -or $result -notmatch 'Sandbox required; host execution refused') { throw 'PowerShell 5.1 host guard failed.' }
$result=& $env:ComSpec /d /c call (Join-Path $PSScriptRoot 'Run-Icon-Upgrade.cmd') --no-pause 2>&1 | Out-String
if ($LASTEXITCODE -ne 1 -or $result -notmatch 'INSIDE the current Windows Sandbox only') { throw 'CMD host guard failed.' }
Write-Output 'PASS fixed .14->.15 interactive dispatch, command allowlist, 9 invalid baselines and two host guards. No installer executed.'
