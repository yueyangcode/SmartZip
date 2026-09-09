$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $root 'src\DeploymentHelper\Program.cs'))
function Assert-DeploymentSafety([string]$code) {
    if($code -match 'CoCreateInstance|CoGetClassObject|GetTypeFromCLSID|Activator.CreateInstance|Process.Kill|taskkill') {throw 'Deployment must not activate packaged COM or kill processes.'}
    foreach($flag in 'ForceAppShutdown','ForceTargetAppShutdown','DeferRegistrationWhenPackagesAreInUse') {
        if($code -notmatch ($flag+'\s*=\s*false')) {throw "Must explicitly disable $flag."}
    }
    $verify=[regex]::Match($code,'(?s)static void VerifyRegistration\(.+?(?=    static PackageHealth)').Value
    if($verify -notmatch 'ReadPackageHealth\(p\);health.RequireHealthy' -or $verify -notmatch 'PackagedCom\\Package' -or $verify -notmatch 'Registered package has no expected context-menu declaration') {throw 'Registration verification must retain health, packaged COM and manifest checks.'}
    $restore=[regex]::Match($code,'(?s)static async Task RestorePreviousPackage.+?(?=    static async Task PrepareUpgrade)').Value
    if($restore -notmatch '(?s)ReadPackageHealth\(present\[0\]\).IsHealthy.+?NeedsPackageRestore.+?RegisterAt\(path,true\).+?VerifyRegistration\(old.Version,path\).+?PREVIOUS_PACKAGE_RESTORED_HEALTHY') {throw 'Rollback must restore an unhealthy same-version package and verify before success.'}
    if($code -notmatch '(?s)Inspect\(previousPath,previous,false\);VerifyRegistration\(previous,previousPath\).+?UPGRADE_BASELINE_OK') {throw 'Preflight must verify health before accepting an old installation.'}
    if($code -notmatch '(?s)await tx.Rollback\(\);VerifyRegistration\(j.Previous!.Version.+?UpgradeBackup.Discard.+?UPGRADE_ROLLBACK_COMPLETE') {throw 'Healthy baseline must be checked before discarding backup and reporting rollback complete.'}
    if($code -notmatch '(?s)UPGRADE_ROLLBACK_INCOMPLETE.+?FileMode.CreateNew.+?JournalJson.Serialize\(j\)') {throw 'Incomplete rollback must preserve an owned recovery journal.'}
    if($code -notmatch 'if\(!r.IsRegistered\)throw') {throw 'Deferred registration is not committed success.'}
}
Assert-DeploymentSafety $source
foreach($mutation in @(
    $source.Replace('health.RequireHealthy(p.Id.FullName);',''),
    $source.Replace('ForceAppShutdown=false','ForceAppShutdown=true'),
    $source.Replace('DeferRegistrationWhenPackagesAreInUse=false','DeferRegistrationWhenPackagesAreInUse=true'),
    $source.Replace('ReadPackageHealth(present[0]).IsHealthy','true'),
    $source.Replace('VerifyRegistration(old.Version,path);',''),
    $source.Replace('FileMode.CreateNew','FileMode.Create'),
    $source.Replace('if(!r.IsRegistered)throw','if(false)throw'),
    ($source + ' CoCreateInstance()')
)) {
    $rejected=$false
    try {Assert-DeploymentSafety $mutation} catch {$rejected=$true}
    if(!$rejected){throw 'Deployment guard failed to detect an unsafe mutation.'}
}
Write-Host 'PASS deployment source wiring and 8 unsafe mutations: no activation/forced shutdown/defer, health before commit, recovery before cleanup.'
