# Instala componentes do Android SDK e aceita licenças automaticamente.
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$sm = "$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat"

Write-Output "=== Aceitando licencas ==="
$y = 'y'
& $sm --licenses 2>$null | ForEach-Object {
    if ($_ -match '\(y/N\)') { $y } else { $_ }
} | Out-Null
Write-Output "licencas ok"

Write-Output "=== Instalando platform-tools, android-35, build-tools 35 ==="
& $sm "platform-tools" "platforms;android-35" "build-tools;35.0.0" 2>$null | Select-Object -Last 3
Write-Output "CONCLUIDO"
