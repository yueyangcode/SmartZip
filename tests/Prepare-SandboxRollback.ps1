[CmdletBinding()]
param([switch]$ContinueAfterLogAudit)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path $project 'build\sandbox-rollback-0.1.0.14'
$previousInput = Join-Path $project 'build\sandbox-rollback-0.1.0.11\Input'
$inputRoot = Join-Path $testRoot 'Input'
$outputRoot = Join-Path $testRoot 'Output'
$publish = Join-Path $project $(if($ContinueAfterLogAudit){'build\tests\sandbox-rollback-0.1.0.14-logfix'}else{'build\tests\sandbox-rollback-0.1.0.14'})

# Prepare materials only. Never run an installer on the host or recreate a Sandbox.
if($ContinueAfterLogAudit) {
    if(!(Test-Path -LiteralPath $inputRoot -PathType Container) -or !(Test-Path -LiteralPath $outputRoot -PathType Container)) { throw 'The existing Sandbox mappings are required.' }
    foreach($name in @('SandboxRollback-logfix.exe','Continue-After-State.cmd')) {
        if(Test-Path -LiteralPath (Join-Path $inputRoot $name)) { throw 'Continuation material already exists; do not overwrite it.' }
    }
} else {
    New-Item -ItemType Directory -Path $inputRoot,$outputRoot -Force | Out-Null
    if (Get-ChildItem -LiteralPath $outputRoot -File) { throw 'The new Sandbox output is already in use; preserve its evidence.' }
    if (Get-ChildItem -LiteralPath $outputRoot -Directory) { throw 'Review the existing rollback run before preparing another.' }
}
$faults = [ordered]@{
    'after-stage' = 'EED84F66738EBABEB4A806273B550EEF12B2C26743CA3A4DABA7F27813CA23F4'
    'after-package' = '5AECBEE9FB361187FC8F665AF1706DA4AFC059BEF3E6C327DB672EE2B166E82C'
    'before-commit' = '4849A480213D5E25B8F6CC786998C2DBEC6B9358FA1599F1CAE3CA87E435C7C6'
    'after-state' = '030A4BDFC0187EA6F92593BD68F989D8956DF7BB96F954BBFF2A54FF751A22EE'
}
foreach ($stage in $faults.Keys) {
    $file = Join-Path $project "dist\SmartZipSetup-0.1.0.14-test-fault-$stage.exe"
    if ((Get-FileHash -LiteralPath $file).Hash -ne $faults[$stage]) { throw "Original fault installer changed: $stage" }
}
Push-Location $project
try {
    & dotnet publish tests\SandboxRollback\SandboxRollback.csproj -c Release -o $publish -p:PublishTrimmed=true -p:TrimMode=link -p:TrimmerSingleWarn=false -p:TreatWarningsAsErrors=true -p:ILLinkTreatWarningsAsErrors=true -p:DebugType=None -p:DebugSymbols=false
    if ($LASTEXITCODE -ne 0) { throw 'Test runner publish failed.' }
    $runner = Join-Path $publish 'SandboxRollback.exe'
    & $runner --selftest
    if ($LASTEXITCODE -ne 0) { throw 'Pure runner self-tests failed.' }
    if ($env:USERNAME -eq 'WDAGUtilityAccount') { throw 'This preparation script is intended for the host build workspace.' }
    $guardResult = & $runner --run 2>&1 | Out-String
    if ($LASTEXITCODE -ne 1 -or $guardResult -notmatch 'Host execution refused') { throw "Host guard did not refuse correctly: $guardResult" }
    $guardResult | Set-Content -LiteralPath (Join-Path $publish 'host-guard.log') -Encoding utf8
    if($ContinueAfterLogAudit) {
        $continuationGuard = & $runner --continue-after-log-audit 2>&1 | Out-String
        if($LASTEXITCODE -ne 1 -or $continuationGuard -notmatch 'Host execution refused') { throw 'Continuation did not refuse host execution.' }
        $continuationGuard | Set-Content -LiteralPath (Join-Path $publish 'continuation-host-guard.log') -Encoding utf8
        & $runner --verify-log-audit (Join-Path $outputRoot 'rollback-run-20260909-212727')
        if($LASTEXITCODE -ne 0) { throw 'Read-only pinned evidence audit failed.' }
        Copy-Item -LiteralPath $runner -Destination (Join-Path $inputRoot 'SandboxRollback-logfix.exe')
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'SandboxRollback\Continue-After-State.cmd') -Destination (Join-Path $inputRoot 'Continue-After-State.cmd')
        Get-FileHash -LiteralPath (Join-Path $inputRoot 'SandboxRollback-logfix.exe')
        Write-Output 'READY: current Sandbox may run only after-state after evidence/live-baseline checks. Old runner, installers and results untouched. No installer started.'
        return
    }
    Copy-Item -LiteralPath $runner -Destination (Join-Path $inputRoot 'SandboxRollback.exe')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'SandboxRollback\Run-Rollback.cmd') -Destination (Join-Path $inputRoot 'Run-Rollback.cmd')
    foreach ($stage in $faults.Keys) {
        $name = "SmartZipSetup-0.1.0.14-test-fault-$stage.exe"
        $destination = Join-Path $inputRoot $name
        if (!(Test-Path -LiteralPath $destination)) { Copy-Item -LiteralPath (Join-Path $project "dist\$name") -Destination $destination }
        if ((Get-FileHash -LiteralPath $destination).Hash -ne $faults[$stage]) { throw "Mapped fault installer hash mismatch: $stage" }
    }
    $baselineName = 'SmartZipSetup-test9-dirfix2.exe'
    $baselineHash = '400F14F16BED047AB489B9187EE519E6DB838C53A764596D595C511DE2368BFF'
    if ((Get-FileHash -LiteralPath (Join-Path $project "dist\$baselineName")).Hash -ne $baselineHash) { throw 'Original baseline installer changed.' }
    Copy-Item -LiteralPath (Join-Path $project "dist\$baselineName") -Destination (Join-Path $inputRoot $baselineName)
    Copy-Item -LiteralPath (Join-Path $previousInput 'Check-Sandbox.cmd') -Destination (Join-Path $inputRoot 'Check-Sandbox.cmd')
    # Reuse the already-tested baseline wrapper, but omit PS provider metadata
    # from its JSON. This keeps evidence small without changing the installation.
    $baselineWrapper = [IO.File]::ReadAllText((Join-Path $previousInput 'Install-Baseline.cmd'))
    $baselineWrapper = $baselineWrapper.Replace("ProductState=(Get-ItemProperty -LiteralPath 'HKCU:\Software\SmartZipModern' -ErrorAction SilentlyContinue)", "ProductState=(Get-ItemProperty -LiteralPath 'HKCU:\Software\SmartZipModern' -ErrorAction SilentlyContinue | Select-Object Publisher,Version,VersionPath,CertificateCreated,CertificateThumbprint,UserSid)")
    [IO.File]::WriteAllText((Join-Path $inputRoot 'Install-Baseline.cmd'), $baselineWrapper, [Text.Encoding]::ASCII)
    $configuration = @"
<Configuration>
  <vGPU>Disable</vGPU><Networking>Disable</Networking>
  <AudioInput>Disable</AudioInput><VideoInput>Disable</VideoInput>
  <PrinterRedirection>Disable</PrinterRedirection><ClipboardRedirection>Disable</ClipboardRedirection>
  <MemoryInMB>4096</MemoryInMB>
  <MappedFolders>
    <MappedFolder><HostFolder>$([Security.SecurityElement]::Escape($inputRoot))</HostFolder><SandboxFolder>C:\SmartZipTestInput</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$([Security.SecurityElement]::Escape($outputRoot))</HostFolder><SandboxFolder>C:\SmartZipTestOutput</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand><Command>cmd.exe /d /c C:\SmartZipTestInput\Check-Sandbox.cmd --no-pause</Command></LogonCommand>
</Configuration>
"@
    [IO.File]::WriteAllText((Join-Path $testRoot 'SmartZip-Rollback-0.1.0.14.wsb'), $configuration, [Text.UTF8Encoding]::new($true))
    Get-FileHash -LiteralPath (Join-Path $inputRoot 'SandboxRollback.exe')
    Write-Output 'READY for a NEW Sandbox baseline. Old Sandbox/evidence untouched. No Sandbox or installer started.'
} finally { Pop-Location }
