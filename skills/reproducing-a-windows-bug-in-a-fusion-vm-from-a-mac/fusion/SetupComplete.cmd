@echo off
rem Runs as SYSTEM at the end of setup, before OOBE creates accounts and before the first logon (win.sh create puts it on the unattend disc).
set L=C:\Users\Public\firstlogon.log
echo %date% %time% setupcomplete start >> %L%
net user __USER__ __PW__ /add /y >> %L% 2>&1
echo net user add exit %errorlevel% >> %L%
net localgroup Administrators __USER__ /add >> %L% 2>&1
echo localgroup add exit %errorlevel% >> %L%
rem fallback login for diagnosis if the guest user is missing (test VM only, same password)
net user Administrator __PW__ /active:yes >> %L% 2>&1
echo administrator enable exit %errorlevel% >> %L%
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\firstlogon.ps1
net localgroup Administrators >> %L% 2>&1
rem it holds the password
del /f /q C:\Windows\Setup\Scripts\SetupComplete.cmd
