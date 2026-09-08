$ErrorActionPreference = 'Stop'
# Source-contract regression guard, not an installed UI/cancellation test.
# Inno 6.2.2: confirmation -> usUninstall (fatal exceptions) -> PerformUninstall.
# https://github.com/jrsoftware/issrc/blob/is-6_2_2/Projects/Uninstall.pas#L620-L655
function Assert-UninstallOrder([string]$Source) {
    $code = ($Source -split '\[Code\]', 2)[1]
    if (!$code) { throw 'Missing installer code.' }
    $code = $code -replace '(?m)//.*$', ''
    if ($code -match '(?i)\b(?:InitializeUninstall|InitializeUninstallProgressForm|DeinitializeUninstall)\b') {
        throw 'No pre-confirmation or shutdown cleanup hook is permitted.'
    }
    $hook = [regex]::Match($code, '(?is)procedure CurUninstallStepChanged\(CurUninstallStep: TUninstallStep\);(?<body>.*)\z')
    if (!$hook.Success) { throw 'Missing final uninstall event handler.' }
    $body = $hook.Groups['body'].Value
    if ($body -notmatch '(?is)begin\s+if CurUninstallStep <> usUninstall then exit;') {
        throw 'Cleanup must be gated to the confirmed usUninstall stage.'
    }
    if ($body -notmatch "(?is)Arguments := 'uninstall';\s+if UninstallSilent then Arguments := Arguments \+ ' --no-ui';\s+CleanupSucceeded := Exec\(ExpandConstant\('[^']+DeploymentHelper.exe'\), Arguments, '', SW_HIDE, ewWaitUntilTerminated, Code\);") {
        throw 'Uninstall must wait for the exact installed helper.'
    }
    if ($body -notmatch '(?is)if CleanupSucceeded then CleanupSucceeded := Code = 0;\s+if not CleanupSucceeded then begin\s+Log\([^\r\n]+;\s+SuppressibleMsgBox\([^\r\n]+;\s+Abort;\s+end;') {
        throw 'Helper launch failure and nonzero exit must abort before Inno deletion.'
    }
    if ([regex]::Matches($code, "'uninstall'").Count -ne 1) { throw 'Unexpected additional uninstall dispatch.' }
}
$source = Get-Content (Join-Path $PSScriptRoot '..\installer\SmartZipModern.iss') -Raw
Assert-UninstallOrder $source
Write-Host 'PASS production uninstall source: post-confirmation gate, synchronous helper, fail-closed abort'
# Deliberately regress each safety boundary. The guard must reject all mutations.
$mutations = @(
    $source.Replace('procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);', 'function InitializeUninstall(): Boolean;'),
    $source.Replace('if CurUninstallStep <> usUninstall then exit;', ''),
    $source.Replace('if CleanupSucceeded then CleanupSucceeded := Code = 0;', ''),
    $source.Replace('    Abort;', ''),
    $source.Replace('ewWaitUntilTerminated, Code);', 'ewNoWait, Code);')
)
foreach ($mutation in $mutations) {
    $rejected = $false
    try { Assert-UninstallOrder $mutation } catch { $rejected = $true }
    if (!$rejected) { throw 'Unsafe uninstall mutation escaped the regression guard.' }
}
Write-Host 'PASS all 5 unsafe uninstall mutations rejected; no installer or helper executed'
