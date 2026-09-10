$ErrorActionPreference = 'Stop'
if ($env:USERNAME -eq 'WDAGUtilityAccount') { throw 'Run source tests on the build host.' }
$allowed = @('Get-CimInstance','Join-Path','Test-Path','Get-AppxPackage','Get-ItemProperty','Get-Content',
    'ConvertFrom-Json','Get-Item','Get-FileHash','New-Item','Out-Null','Under','Get-ChildItem','Where-Object',
    'Get-Process','Select-Object','ConvertTo-Json','Set-Content','Write-Output','ForEach-Object','Sort-Object',
    'Get-WinEvent','Format-Table','FileTree','Snapshot','Start-Process','Clean')
foreach ($name in @('Prepare-Functional-Tests.cmd','Collect-Functional-Results.cmd','Run-Normal-Uninstall.cmd','Run-Normal-Reinstall.cmd')) {
    $path = Join-Path $PSScriptRoot $name
    $text = [IO.File]::ReadAllText($path)
    $line = @($text -split '\r?\n' | Where-Object { $_ -match '^"%SystemRoot%.* -Command "' })
    if ($line.Count -ne 1 -or $line[0].Length -ge 8000) { throw "CMD length/command error: $name" }
    $payload = [regex]::Match($line[0], ' -Command "(.*)"$').Groups[1].Value
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($payload,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    foreach ($command in $ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true)) {
        if ($command.GetCommandName() -notin $allowed) { throw "Unexpected command in ${name}: $command" }
    }
    foreach ($forbidden in @('Add-AppxPackage','Remove-AppxPackage','Import-Certificate','Remove-Item',
        'Stop-Process','Set-ExecutionPolicy','CreateSubKey','SetValue(', 'File]::Delete','File]::Move','SmartZip.exe')) {
        if ($text.Contains($forbidden)) { throw "Unexpected operation in ${name}: $forbidden" }
    }
    if ($name -eq 'Run-Normal-Uninstall.cmd') {
        if ([regex]::Matches($payload,'\bStart-Process\b').Count -ne 1 -or
            !$payload.Contains('Start-Process -FilePath $uninstaller -ArgumentList') -or
            !$payload.Contains("`$uninstaller=Join-Path `$root 'unins000.exe'") -or
            !$payload.Contains('$arp.UninstallString -ne ([string][char]34+$uninstaller+[char]34)') -or
            !$payload.Contains('-WindowStyle Normal -PassThru -Wait') -or !$payload.Contains('/NORESTART /LOG=') -or
            !$payload.Contains('Uninstall test evidence already exists. No automatic retry.') -or
            $payload.Contains('/SILENT') -or $payload.Contains('/VERYSILENT')) { throw 'Uninstall must use exactly the verified normal interactive entry once, with before/after evidence.' }
    } elseif ($name -eq 'Run-Normal-Reinstall.cmd') {
        if ([regex]::Matches($payload,'\bStart-Process\b').Count -ne 1 -or
            !$payload.Contains('Start-Process -FilePath $installer -ArgumentList') -or
            !$payload.Contains("`$installer='C:\SmartZipTestInput\SmartZipSetup-0.1.0.14-test.exe'") -or
            !$payload.Contains('C8A9C6F0D3B18D3DFA3D276F3E7C10BD3732771054DF3EED1B8970F5F58594E1') -or
            !$payload.Contains('if(!(Clean $before))') -or !$payload.Contains('Reinstall evidence already exists. No automatic retry.') -or
            !$payload.Contains('-WindowStyle Normal -PassThru -Wait') -or !$payload.Contains('/NORESTART /LOG=') -or
            $payload.Contains('/SILENT') -or $payload.Contains('/VERYSILENT')) { throw 'Reinstall must dispatch the fixed hash-checked normal installer after clean-state checks, without silent consent.' }
        $cleanFunction=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Clean'},$true))
        if ($cleanFunction.Count -ne 1) { throw 'Clean-state predicate missing.' }
        . ([scriptblock]::Create($cleanFunction[0].Extent.Text))
        $empty=@{RootExists=$false;ProductStateExists=$false;UninstallEntryExists=$false;ShortcutDirectoryExists=$false;NativeComCU=$false;NativeComLM=$false;TrustOwnershipKeyExists=$false;Packages=@();PackagedCom=@();Certificates=@()}
        if (!(Clean $empty)) { throw 'Empty registration state was not recognized.' }
        foreach ($key in @('RootExists','ProductStateExists','UninstallEntryExists','ShortcutDirectoryExists','NativeComCU','NativeComLM','TrustOwnershipKeyExists')) {
            $dirty=$empty.Clone(); $dirty[$key]=$true
            if (Clean $dirty) { throw "Leftover accepted: $key" }
        }
        foreach ($key in @('Packages','PackagedCom')) {
            $dirty=$empty.Clone(); $dirty[$key]=@('remaining registration')
            if (Clean $dirty) { throw "Leftover accepted: $key" }
        }
        foreach ($certificate in @(@{Visible=$true;PhysicalKeyExists=$false},@{Visible=$false;PhysicalKeyExists=$true})) {
            $dirty=$empty.Clone(); $dirty.Certificates=@($certificate)
            if (Clean $dirty) { throw 'Remaining certificate accepted.' }
        }
    } elseif ($text.Contains('Start-Process')) { throw 'Only the formal installer/uninstaller wrappers may launch a process.' }
    $guard=& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command $payload 2>&1 | Out-String
    if ($LASTEXITCODE -ne 1 -or $guard -notmatch 'Sandbox required; host execution refused') { throw "PowerShell host guard failed: $guard" }
    $guard=& $env:ComSpec /d /c call $path --no-pause 2>&1 | Out-String
    if ($LASTEXITCODE -ne 1 -or $guard -notmatch 'INSIDE Windows Sandbox only') { throw "CMD host guard failed: $guard" }
    if ($name -eq 'Collect-Functional-Results.cmd') {
        $start=$payload.IndexOf('$same='); $end=$payload.IndexOf('; [pscustomobject]@{Case=',$start)
        if ($start -lt 0 -or $end -le $start) { throw 'Content observation logic not located.' }
        $observation=[scriptblock]::Create($payload.Substring($start,$end-$start)+'; $status')
        foreach ($case in @(
            @{Expected=@('A');Actual=@('A');Changed=@();Result='EXPECTED_CONTENT_PRESENT'},
            @{Expected=@('A','B');Actual=@('A','B');Changed=@();Result='EXPECTED_CONTENT_PRESENT'},
            @{Expected=@('A');Actual=@();Changed=@();Result='NOT_OBSERVED_OR_MISMATCH'},
            @{Expected=@('A');Actual=@('B');Changed=@();Result='NOT_OBSERVED_OR_MISMATCH'},
            @{Expected=@('A');Actual=@('A','A');Changed=@();Result='NOT_OBSERVED_OR_MISMATCH'},
            @{Expected=@();Actual=@();Changed=@();Result='NO_EXTRACTION_OUTPUT_PRESENT'},
            @{Expected=@('A');Actual=@('A');Changed=@('archive.zip');Result='INPUT_CHANGED'})) {
            $expected=$case.Expected; $actual=$case.Actual; $changed=$case.Changed
            if ((& $observation) -ne $case.Result) { throw 'Observation classified an untested/damaged/repeated case incorrectly.' }
        }
    }
}
Write-Output 'PASS: parser/command bounds, command allowlist, Windows PowerShell 5.1 and CMD host guards, content checks, clean-state rejection cases, fixed interactive installer/uninstaller dispatch.'
