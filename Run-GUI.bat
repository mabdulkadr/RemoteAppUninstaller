@ECHO OFF
TITLE Remote App Uninstaller
ECHO Starting Remote App Uninstaller...
POWERSHELL.EXE -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0RemoteAppUninstaller.ps1"
IF ERRORLEVEL 1 ECHO The script exited with an error.
PAUSE
