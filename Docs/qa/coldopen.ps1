. C:\Code\StarCodex\Docs\qa\qa-env.ps1
# Poll screencaps for cold-open timing; filename ST=HHmmss.fff
$out = "C:\Code\StarCodex\Docs\qa\shots"
for ($i = 0; $i -lt 30; $i++) {
  adb shell screencap -p /sdcard/qa.png
  $n = Get-Date -Format "HHmmss.fff"
  adb pull /sdcard/qa.png "$out\ST_$n.png" | Out-Null
  Start-Sleep -Milliseconds 500
}
