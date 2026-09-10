@echo off
setlocal
if /i not "%USERNAME%"=="WDAGUtilityAccount" (
  echo STOP: Run this INSIDE the current Windows Sandbox only.
  if /i not "%~1"=="--no-pause" pause
  exit /b 1
)
echo Upgrade SmartZip 0.1.0.14 to 0.1.0.15 INSIDE this Sandbox only.
echo Keep the existing C:\SmartZip installation directory. Do NOT uninstall first.
echo Complete the normal wizard. Keep this window and Sandbox open.
echo No cleanup, repair, forced shutdown or certificate import by this runner.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command "& ([scriptblock]::Create([IO.File]::ReadAllText('C:\SmartZipTestInput\Run-Icon-Upgrade.ps1')))"
set "test_exit=%ERRORLEVEL%"
echo Test collection exit code: %test_exit%
echo Send this result before proceeding. Keep Sandbox open.
if /i not "%~1"=="--no-pause" pause
exit /b %test_exit%
