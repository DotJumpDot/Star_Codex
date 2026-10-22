@echo off
rem Windowed boot for AVD "StarCodex" - for looking at the app yourself.
rem Same as boot-emu-low.bat but WITH a window, no CPU/RAM caps, and the
rem quick path (-no-snapshot off is NOT used: cold boots are fine, app
rem installs persist across reboots).
rem Usage:   scripts\boot-emu.bat [guestRamMB]
rem Example: scripts\boot-emu.bat 3072
rem Stop:    adb emu kill  (or just close the window)

setlocal
set "EMU=%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe"
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
set "MEM=%~1"
if not defined MEM set "MEM=3072"

powershell -NoProfile -Command "$e=@(Get-Process qemu-system* -ErrorAction SilentlyContinue); if($e.Count -gt 0){Write-Output 'REUSED already-running emulator'}else{Start-Process -FilePath '%EMU%' -ArgumentList '-avd','StarCodex','-gpu','swiftshader_indirect','-no-boot-anim','-no-audio','-memory','%MEM%'; Write-Output ('STARTED windowed, guest RAM %MEM% MB')}"

powershell -NoProfile -Command "& '%ADB%' wait-for-device; for($i=0;$i -lt 40;$i++){ $c = & '%ADB%' shell getprop sys.boot_completed 2>$null; if($c -match '1'){Write-Output 'BOOTED - stop later with: adb emu kill'; exit 0}; Start-Sleep -Seconds 3 }; Write-Output 'NOT BOOTED after ~2 min - check the emulator window'; exit 1"

endlocal & exit /b %errorlevel%
