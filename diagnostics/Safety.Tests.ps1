$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Program.cs'))
$project = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PreflightProbe.csproj'))
$iss = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PreflightDiagnostic.iss'))
foreach ($forbidden in 'AddPackage','RemovePackage','CreateSubKey','SetValue(','DeleteSubKey','TrustBroker','Process.Start(','Directory.Create','File.Delete','File.Copy','File.Move','HttpClient','X509Store') {
    if ($source.Contains($forbidden)) { throw "Diagnostic contains forbidden operation: $forbidden" }
}
if ([regex]::Matches($project,'<Compile Include=').Count -ne 1 -or !$project.Contains('UserContext.cs')) { throw 'Unexpected production code linked.' }
if ($iss -match '(?im)^\[(Icons|Registry|Run|UninstallRun|UninstallDelete|Dirs|InstallDelete)\]') { throw 'Diagnostic wrapper has a mutation section.' }
if (!$iss.Contains('Uninstallable=no') -or !$iss.Contains('CreateUninstallRegKey=no')) { throw 'Diagnostic must not install uninstall metadata.' }
if ($iss -match "Result\s*:=\s*''" -or !$iss.Contains('function PrepareToInstall') -or !$iss.Contains('flags: dontcopy'.Replace('flags','Flags'))) {
    throw 'Diagnostic stop/extraction contract missing.'
}
$calls = [regex]::Matches($source,'File\.(AppendAllText|WriteAllText|WriteAllBytes)\(')
if ($calls.Count -ne 1 -or !$source.Contains('File.AppendAllText(LogPath,')) { throw 'Only append to the dedicated diagnostic log is allowed.' }
Write-Host 'PASS diagnostic source guard: no deployment/registry/certificate mutations; wrapper always stops'
