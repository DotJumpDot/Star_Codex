@echo off
rem Windowed boot for AVD "StarCodex" - for looking at the app yourself.
rem Same as boot-emu-low.bat but WITH a window and no CPU/RAM caps.
rem ALWAYS cold-boots (-no-snapshot): a quick-boot snapshot restored under
rem a different host GPU state corrupts the guest GL stack — system UI
rem renders but Flutter's Impeller GLES draws BLACK (2026-10-24). App
rem installs persist across cold boots anyway.
rem Usage:   scripts\boot-emu.bat [guestRamMB]
rem Example: scripts\boot-emu.bat 3072
rem Stop:    adb emu kill  (or just close the window)

setlocal
set "EMU=%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe"
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
set "MEM=%~1"
if not defined MEM set "MEM=3072"

powershell -NoProfile -Command "$e=@(Get-Process qemu-system* -ErrorAction SilentlyContinue); if($e.Count -gt 0){Write-Output 'REUSED already-running emulator'}else{Start-Process -FilePath '%EMU%' -ArgumentList '-avd','StarCodex','-no-snapshot','-gpu','swiftshader_indirect','-no-boot-anim','-no-audio','-memory','%MEM%'; Write-Output ('STARTED windowed, guest RAM %MEM% MB')}"

powershell -NoProfile -Command "& '%ADB%' wait-for-device; for($i=0;$i -lt 40;$i++){ $c = & '%ADB%' shell getprop sys.boot_completed 2>$null; if($c -match '1'){Write-Output 'BOOTED - stop later with: adb emu kill'; exit 0}; Start-Sleep -Seconds 3 }; Write-Output 'NOT BOOTED after ~2 min - check the emulator window'; exit 1"

endlocal & exit /b %errorlevel%
