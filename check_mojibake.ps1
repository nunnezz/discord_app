$files = Get-ChildItem -Path "c:\Users\nunes\Downloads\projetos\discord_app\lib","c:\Users\nunes\Downloads\projetos\discord_app\test" -Recurse -Include *.dart -ErrorAction SilentlyContinue
foreach ($f in $files) {
  $rel = $f.FullName.Replace('c:\Users\nunes\Downloads\projetos\discord_app\','')
  $n = 0
  foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
    $n++
    if ($line -match "\u00C3[\u00A3\u00A7\u00A9\u00AA\u00AD\u00B3\u00B4\u00B5\u00A1\u00BA\u0087\u0089\u0153\u201A]|\u00E3|\u00E7|\u00E9|\u00EA|\u00ED|\u00F3|\u00F4|\u00F5|\u00E1|\u00E0|\u00FA|\u00C7|\u00C9|\u00D3") {
      $t = $line.Trim()
      if ($t.Length -gt 90) { $t = $t.Substring(0,90) }
      Write-Output "${rel}:${n}: $t"
    }
  }
}
