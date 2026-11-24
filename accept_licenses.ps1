# Aceita todas as licencas do SDK via echo y em lote (cmd para piping confiavel).
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$sm = "$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat"

# Gera um arquivo com muitos "y" e redireciona como stdin.
$yesFile = "$env:TEMP\yes_input.txt"
("y`r`n" * 30) | Set-Content $yesFile -NoNewline

cmd /c "`"$sm`" --licenses < `"$yesFile`"" 2>$null | Out-String | ForEach-Object {
    ($_ -split "`n") | Select-String "All SDK package licenses accepted|100%|Accept" | Select-Object -Last 4
}
