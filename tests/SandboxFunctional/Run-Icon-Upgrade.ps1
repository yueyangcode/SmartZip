# Fixed one-shot .14 -> .15 smoke-test launcher for the existing Sandbox only.
# Reuses the normal installer and previous snapshot/log collection approach.
$ErrorActionPreference = 'Stop'
$evidence = $null
try {
    if ($env:USERNAME -ne 'WDAGUtilityAccount' -or (Get-CimInstance Win32_ComputerSystem).Model -ne 'Virtual Machine') {
        throw 'Sandbox required; host execution refused.'
    }
    $output = 'C:\SmartZipTestOutput'
    $reviewed = Join-Path $output 'normal-reinstall-0.1.0.14\result.json'
    if ((Get-FileHash -LiteralPath $reviewed).Hash -ne '4F49B30E7536E0AFE4596593199228C54F04F9C0E35AA781D351253A7F7211B2') { throw 'Reviewed reinstall evidence missing or changed.' }
    $prior = Get-Content -LiteralPath $reviewed -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($prior.InstallerExitCode -ne 0 -or $prior.After.Computer -ne $env:COMPUTERNAME) { throw 'Wrong Sandbox or unsuccessful prior reinstall.' }
    $installer = 'C:\SmartZipTestInput\SmartZipSetup-0.1.0.15-test.exe'
    $expectedHash = '1AED980A38A21BFC5BC3C92410C5895A2B852F6E2680454AEAECDA9D5F815E2D'
    if ((Get-FileHash -LiteralPath $installer).Hash -ne $expectedHash) { throw 'Installer hash mismatch.' }
    # The reviewed reinstall used C:\SmartZip, NOT the old LOCALAPPDATA default.
    $root = 'C:\SmartZip'
    $stateKey = 'HKCU:\Software\SmartZipModern'
    $uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{DA975784-DC84-48EF-9A47-F60C0C969280}_is1'
    $thumb = 'A1709CED9DB02150E2FB40CE6496BD1938D89195'
    $clsid = '{C12835D9-8B49-48D9-AE52-5E66D31209E1}'
    function FileTree($path) {
        if (!(Test-Path -LiteralPath $path)) { return }
        if (((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Linked project root refused.' }
        $entries = @(Get-ChildItem -LiteralPath $path -Recurse -Force)
        if (@($entries | Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0}).Count) { throw 'Linked project data refused.' }
        $entries | Where-Object {!$_.PSIsContainer} | Sort-Object FullName | ForEach-Object {
            [pscustomobject]@{Path=$_.FullName.Substring($path.Length+1); Bytes=$_.Length; SHA256=(Get-FileHash -LiteralPath $_.FullName).Hash}
        }
    }
    function Snapshot {
        [ordered]@{
            CapturedUtc=[DateTime]::UtcNow.ToString('o'); Computer=$env:COMPUTERNAME; Root=$root
            EnableLUA=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').EnableLUA
            State=$(if(Test-Path -LiteralPath $stateKey){Get-ItemProperty -LiteralPath $stateKey | Select-Object Version,VersionPath,Publisher,UserSid,CertificateCreated,CertificateThumbprint})
            Uninstall=$(if(Test-Path -LiteralPath $uninstallKey){Get-ItemProperty -LiteralPath $uninstallKey | Select-Object DisplayVersion,InstallLocation,UninstallString})
            Files=@(FileTree $root)
            UserConfig=@(FileTree (Join-Path $env:LOCALAPPDATA 'SmartZip Modern\UserData'))
            ShortcutFiles=@(FileTree (Join-Path ([Environment]::GetFolderPath('Programs')) 'SmartZip'))
            Packages=@(foreach($package in @(Get-AppxPackage -Name SmartZip.Modern)) {
                $manifest=Get-AppxPackageManifest -Package $package.PackageFullName
                [pscustomobject]@{
                    FullName=$package.PackageFullName; Version=$package.Version.ToString(); Publisher=$package.Publisher; Status=$package.Status.ToString()
                    PackagedComClassExists=(Test-Path -LiteralPath ('Registry::HKEY_CLASSES_ROOT\PackagedCom\Package\'+$package.PackageFullName+'\Class\'+$clsid))
                    Manifest=$manifest.OuterXml
                }
            })
            Certificates=@(foreach($location in @('LocalMachine','CurrentUser')) { foreach($store in @('TrustedPeople','Root')) {
                $path='Cert:\'+$location+'\'+$store+'\'+$thumb
                $physical=$(if($location -eq 'LocalMachine'){'HKLM:'}else{'HKCU:'})+'\SOFTWARE\Microsoft\SystemCertificates\'+$store+'\Certificates\'+$thumb
                $certificate=if(Test-Path -LiteralPath $path){Get-Item -LiteralPath $path}else{$null}
                [pscustomobject]@{Store=$location+'\'+$store; Visible=($null -ne $certificate); PhysicalKeyExists=(Test-Path -LiteralPath $physical); Subject=$certificate.Subject; HasPrivateKey=$certificate.HasPrivateKey}
            }})
            Explorer=@(Get-Process explorer -ErrorAction SilentlyContinue | Select-Object Id,StartTime)
        }
    }
    function Healthy($snapshot, $version) {
        $packages=@($snapshot.Packages)
        return ($snapshot.State.Version -eq $version -and $snapshot.State.VersionPath -eq "$root\Versions\$version" -and
            $snapshot.State.Publisher -eq 'CN=SmartZip Modern Evaluation' -and
            $snapshot.State.UserSid -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -and $snapshot.State.CertificateThumbprint -eq $thumb -and
            $snapshot.Uninstall.DisplayVersion -eq $version -and $snapshot.Uninstall.InstallLocation.TrimEnd('\') -eq $root -and
            $packages.Count -eq 1 -and $packages[0].Version -eq $version -and $packages[0].Status -eq 'Ok' -and
            $packages[0].Publisher -eq 'CN=SmartZip Modern Evaluation' -and $packages[0].PackagedComClassExists -and
            @($snapshot.Files | Where-Object {$_.Path -eq "Versions\$version\SmartZip.exe"}).Count -eq 1)
    }
    $target=Join-Path $output 'normal-upgrade-0.1.0.15'
    if (Test-Path -LiteralPath $target) { throw 'Evidence already exists. No automatic retry.' }
    $before=Snapshot
    if (!(Healthy $before '0.1.0.14')) { throw 'Live .14 baseline is not healthy at the reviewed path; no repair attempted.' }
    New-Item -ItemType Directory -Path $target | Out-Null
    $evidence=$target
    $before | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $evidence 'before.json') -Encoding UTF8
    if ((Get-FileHash -LiteralPath $installer).Hash -ne $expectedHash) { throw 'Installer changed after snapshot.' }
    $log=Join-Path $evidence 'upgrade-inno.log'
    # Deliberately interactive: the user completes the normal wizard/consent.
    $process=Start-Process -FilePath $installer -ArgumentList ('/NORESTART /LOG='+[char]34+$log+[char]34) -WindowStyle Normal -PassThru -Wait
    $after=Snapshot
    $configUnchanged=(($before.UserConfig | ConvertTo-Json -Compress) -eq ($after.UserConfig | ConvertTo-Json -Compress))
    $certificateUnchanged=(($before.Certificates | ConvertTo-Json -Compress) -eq ($after.Certificates | ConvertTo-Json -Compress))
    $oldVersionUnchanged=((@($before.Files | Where-Object {$_.Path.StartsWith('Versions\0.1.0.14\')}) | ConvertTo-Json -Compress) -eq
        (@($after.Files | Where-Object {$_.Path.StartsWith('Versions\0.1.0.14\')}) | ConvertTo-Json -Compress))
    $newIcon=@($after.Files | Where-Object {$_.Path -eq 'Versions\0.1.0.15\Assets\SmartZip.ico'})
    $iconMatches=($newIcon.Count -eq 1 -and $newIcon[0].SHA256 -eq '0F0F2E6467718761368A37273D965D70A59AE6C485398FE62C9C4B228DB8CED5')
    $passed=($process.ExitCode -eq 0 -and (Healthy $after '0.1.0.15') -and $configUnchanged -and $certificateUnchanged -and $iconMatches -and $oldVersionUnchanged)
    [ordered]@{
        InstallerExitCode=$process.ExitCode; InstallerSHA256=$expectedHash; DeploymentChecksPassed=$passed
        ConfigUnchanged=$configUnchanged; CertificateStateUnchanged=$certificateUnchanged; InstalledIconMatches=$iconMatches
        OldVersionFilesUnchanged=$oldVersionUnchanged
        After=$after; Note='Menu/icon UI and extraction still require user validation. No manual cleanup, registration or certificate repair.'
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $evidence 'result.json') -Encoding UTF8
    $logs=Join-Path $evidence 'helper-logs'
    New-Item -ItemType Directory -Path $logs | Out-Null
    $copied=@(foreach($source in @(Get-ChildItem -LiteralPath $env:TEMP -Filter 'SmartZip-0.1.0.15-*.log' -File)) {
        if (($source.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Linked helper log refused.' }
        $hash=(Get-FileHash -LiteralPath $source.FullName).Hash
        $copy=Join-Path $logs $source.Name
        [IO.File]::Copy($source.FullName,$copy,$false)
        if ((Get-FileHash -LiteralPath $copy).Hash -ne $hash -or (Get-FileHash -LiteralPath $source.FullName).Hash -ne $hash) { throw 'Log changed; preserve partial evidence.' }
        [pscustomobject]@{Name=$source.Name; SHA256=$hash; Bytes=$source.Length}
    })
    $copied | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'logs.json') -Encoding UTF8
    Write-Output ('INSTALLER EXIT: '+$process.ExitCode)
    Write-Output ('DEPLOYMENT CHECKS: '+$passed)
    Write-Output $evidence
    if (!$passed) { throw 'Upgrade check failed. Stop; no manual repair or further tests.' }
    Write-Output 'Keep Sandbox open. Report this result, then check new icons and one ZIP manually.'
    exit 0
} catch {
    if ($evidence) { [IO.File]::WriteAllText((Join-Path $evidence 'test-error.txt'),$_.Exception.ToString()) }
    [Console]::Error.WriteLine($_.Exception.ToString())
    exit 1
}
