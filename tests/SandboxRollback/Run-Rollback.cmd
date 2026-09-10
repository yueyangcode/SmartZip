@echo off
setlocal
if /i not "%USERNAME%"=="WDAGUtilityAccount" (
  echo STOP: Run this INSIDE the existing Windows Sandbox only.
  pause
  exit /b 1
)
echo Four intentional upgrade-failure tests. Keep this window and Sandbox open.
echo Do not use SmartZip or right-click its files while deployment is running.
echo Any failure stops later tests. No manual cleanup or repair will be performed.
"C:\SmartZipTestInput\SandboxRollback.exe" --run
set "rollback_exit=%ERRORLEVEL%"
echo Test runner exit code: %rollback_exit%
echo Evidence: C:\SmartZipTestOutput\rollback-run-*
echo Keep Sandbox open and send this result to the developer.
pause
exit /b %rollback_exit%
