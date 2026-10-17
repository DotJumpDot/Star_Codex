# qa-env.ps1 — source this in every shell: . C:\Code\StarCodex\Docs\qa\qa-env.ps1
$env:PATH = "C:\Users\jamej\AppData\Local\Android\Sdk\platform-tools;C:\Users\jamej\AppData\Local\Android\Sdk\emulator;" + $env:PATH
$env:PKG = "com.jamej.starcodex"
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17"  # verified below if used
