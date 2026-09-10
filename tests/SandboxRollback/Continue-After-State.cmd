@echo off
setlocal
if /i not "%USERNAME%"=="WDAGUtilityAccount" (
  echo STOP: Run this INSIDE the existing Windows Sandbox only.
  pause
  exit /b 1
)
echo Continue ONLY the fourth SmartZip 0.1.0.14 fault test: after-state.
echo Earlier evidence and the current baseline must verify before testing.
echo No reinstall, manual cleanup, forced shutdown or normal upgrade.
echo Do not use SmartZip or right-click its files. Keep Sandbox open.
"C:\SmartZipTestInput\SandboxRollback-logfix.exe" --continue-after-log-audit
set "continuation_exit=%ERRORLEVEL%"
echo Continuation exit code: %continuation_exit%
echo Evidence: C:\SmartZipTestOutput\rollback-continuation-20260909-212727-after-state
echo Keep Sandbox open and send this result to the developer.
pause
exit /b %continuation_exit%
