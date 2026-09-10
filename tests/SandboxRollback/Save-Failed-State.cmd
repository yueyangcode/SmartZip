@echo off
setlocal
if /i not "%USERNAME%"=="WDAGUtilityAccount" (
  echo STOP: Run this INSIDE the original Windows Sandbox only.
  pause
  exit /b 1
)
echo Exporting ONLY the known SmartZip failed-test backup and ownership receipts.
echo No installation, package registration, certificate change or cleanup.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command "$ErrorActionPreference='Stop'; try {if($env:USERNAME -ne 'WDAGUtilityAccount' -or (Get-CimInstance Win32_ComputerSystem).Model -ne 'Virtual Machine'){throw 'Sandbox required.'}; $out='C:\SmartZipTestOutput'; $run=$out+'\rollback-run-20260909-194513'; $probe=Get-Content -LiteralPath ($out+'\probe.json') -Raw | ConvertFrom-Json; if($probe.Computer -ne $env:COMPUTERNAME){throw 'Different Sandbox session.'}; $before=Get-Content -LiteralPath ($run+'\before-commit\before.json') -Raw | ConvertFrom-Json; $after=Get-Content -LiteralPath ($run+'\before-commit\after.json') -Raw | ConvertFrom-Json; $app=$env:LOCALAPPDATA+'\Programs\SmartZip'; $files=@(@('.upgrade-2084b70b78b24dcba026492a9ed60008\backup.json','backup.json','A0CF077B8B68F18DF59B428896D8C56B64F479642D309EAAFDD399978ADFE062'),@('Versions\0.1.0.8\installed.json','installed-0.1.0.8.json',$before.'files/Versions/0.1.0.8/installed.json'),@('Versions\0.1.0.11\.install-transaction','new-version-marker.txt',$after.'files/Versions/0.1.0.11/.install-transaction'),@('.install-transaction','root-marker.txt',$before.'files/.install-transaction')); foreach($f in $files){if(!$f[2] -or (Get-FileHash -LiteralPath ($app+'\'+$f[0])).Hash -ne $f[2]){throw ('Evidence changed: '+$f[0])}}; $dest=$run+'\preserved-recovery-files'; New-Item -ItemType Directory -Path $dest -Force | Out-Null; foreach($f in $files){$target=$dest+'\'+$f[1]; if(Test-Path -LiteralPath $target){if((Get-FileHash -LiteralPath $target).Hash -ne $f[2]){throw ('Existing export differs: '+$target)}}else{Copy-Item -LiteralPath ($app+'\'+$f[0]) -Destination $target}; if((Get-FileHash -LiteralPath $target).Hash -ne $f[2]){throw 'Export verification failed.'}}; Write-Output ('PASS: 4 evidence files exported and SHA-256 verified. '+$dest); exit 0} catch {[Console]::Error.WriteLine($_.Exception.ToString()); exit 1}"
set "export_exit=%ERRORLEVEL%"
echo Export exit code: %export_exit%
echo Keep Sandbox open. Send this result to the developer before further tests.
pause
exit /b %export_exit%
