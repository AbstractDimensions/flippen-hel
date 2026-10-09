@echo off
REM One-click launcher. Right-click -> Send to Desktop (shortcut) if you want it next to Termite.
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0FlipRunner.ps1" %*
