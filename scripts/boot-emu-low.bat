@echo off
rem Low-impact headless boot for AVD "StarCodex" (on-device QA via adb).
rem Caps, with NO persistent AVD changes:
rem   - guest RAM: arg 1, default 2048 MB (was 3072)
rem   - CPU: QEMU pinned to the top 2 host threads (hard cap) + BelowNormal
rem     priority, so foreground work (e.g. a game) always preempts it
rem   - GPU: untouched - swiftshader renders on CPU by design, so the
rem     emulator never competes for the real GPU
rem Usage:   scripts\boot-emu-low.bat [guestRamMB]
rem Example: scripts\boot-emu-low.bat 1536
rem Stop:    adb emu kill
rem Note: boot is SLOW while the host is busy (10-20 min is normal); the
rem script waits and reports BOOTED when sys.boot_completed=1.

setlocal
set "EMU=%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe"
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
set "MEM=%~1"
if not defined MEM set "MEM=2048"

powershell -NoProfile -Command "$e=@(Get-Process qemu-system* -ErrorAction SilentlyContinue); if($e.Count -gt 0){Write-Output 'REUSED already-running emulator'}else{Start-Process -FilePath '%EMU%' -ArgumentList '-avd','StarCodex','-no-window','-no-snapshot','-no-boot-anim','-no-audio','-gpu','swiftshader_indirect','-memory','%MEM%' -WindowStyle Hidden; Write-Output ('STARTED headless, guest RAM %MEM% MB')}"

powershell -NoProfile -Command "$p=@(); for($i=0;$i -lt 120;$i++){ $p=@(Get-Process qemu-system* -ErrorAction SilentlyContinue); if($p.Count -gt 0){break}; Start-Sleep -Seconds 1 }; if($p.Count -eq 0){Write-Output 'ERROR: no qemu process after 120s'; exit 1}; $n=[int]$env:NUMBER_OF_PROCESSORS; if($n -lt 4){$mask=[int64]3}else{$mask=[int64]3 -shl ($n-2)}; $p|ForEach-Object{$_.PriorityClass='BelowNormal'; $_.ProcessorAffinity=[IntPtr]$mask}; Write-Output ('CAPPED priority=BelowNormal affinity=0x'+$mask.ToString('X')+' on '+$n+' threads ('+$p.Count+' qemu process(es)')"

powershell -NoProfile -Command "& '%ADB%' wait-for-device; for($i=0;$i -lt 80;$i++){ $c = & '%ADB%' shell getprop sys.boot_completed 2>$null; if($c -match '1'){Write-Output 'BOOTED - stop later with: adb emu kill'; exit 0}; Start-Sleep -Seconds 15 }; Write-Output 'NOT BOOTED after ~20 min (slow host? expected while gaming). Poll with: adb shell getprop sys.boot_completed'; exit 1"

endlocal & exit /b %errorlevel%
