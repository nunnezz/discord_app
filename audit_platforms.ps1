$files = Get-ChildItem -Path "c:\Users\nunes\Downloads\projetos\discord_app\lib" -Recurse -Include *.dart
foreach ($f in $files) {
  $rel = $f.FullName.Replace('c:\Users\nunes\Downloads\projetos\discord_app\lib\','')
  $n = 0
  foreach ($line in Get-Content $f.FullName) {
    $n++
    if ($line -match "dart:io|dart:html|dart:js|package:web|Platform\.is|kIsWeb|defaultTargetPlatform") {
      $trimmed = $line.Trim()
      if ($trimmed.Length -gt 100) { $trimmed = $trimmed.Substring(0,100) }
      Write-Output "${rel}:${n}: $trimmed"
    }
  }
}
