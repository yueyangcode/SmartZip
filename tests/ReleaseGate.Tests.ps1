param([Parameter(Mandatory)][string]$TestInstaller,[Parameter(Mandatory)][string]$Version)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
function Reject([string]$Script,[string[]]$Arguments,[string]$Expected){
    $info=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($name in 'SMARTZIP_SIGN_PFX','SMARTZIP_SIGN_PASSWORD','SMARTZIP_PUBLISHER'){$info.Environment.Remove($name)|Out-Null}
    foreach($arg in @('-NoProfile','-NonInteractive','-File',$Script)+$Arguments){$info.ArgumentList.Add($arg)}
    $p=[Diagnostics.Process]::Start($info)
    $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
    if(!$p.WaitForExit(30000)){throw 'Release gate test did not stop promptly.'}
    $output=$stdout.Result+$stderr.Result
    if($p.ExitCode -eq 0 -or !$output.Contains($Expected)){throw "Release safety gate failed: $Expected`n$output"}
    $p.Dispose()
}
Reject (Join-Path $root 'build.ps1') @('-Signing','Release') 'Release blocked: supply a trusted'
Reject (Join-Path $root 'build.ps1') @('-Version','0.01.0.9') 'Use an exact four-part'
Reject (Join-Path $root 'release\New-WinGetManifest.ps1') @('-Installer',$TestInstaller,'-Version',$Version) 'A matching production installer is required'
$folder=Join-Path $root ('build\tests\release-gates-'+[guid]::NewGuid().ToString('N'))
$renamed=Join-Path $folder "SmartZipSetup-$Version-x64.exe"
New-Item -ItemType Directory -Path $folder | Out-Null
try{
    Copy-Item -LiteralPath $TestInstaller -Destination $renamed
    Reject (Join-Path $root 'release\New-WinGetManifest.ps1') @('-Installer',$renamed,'-Version',$Version) 'WinGet generation blocked'
}finally{
    if(Test-Path -LiteralPath $renamed){Remove-Item -LiteralPath $renamed}
    [IO.Directory]::Delete($folder,$false)
}
Write-Host 'PASS release gates: missing signing material, invalid version, test installer and renamed self-signed test installer all rejected. Nothing installed or published.'
