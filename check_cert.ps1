$patterns = 'AGORA_APP_CERTIFICATE|AppCertificate|RtcTokenBuilder'
$files = Get-ChildItem -Path "c:\Users\nunes\Downloads\projetos\discord_app" -Recurse -Include *.dart,*.ts,*.js,*.sql,*.yaml,*.md,*.ps1 |
  Where-Object { $_.FullName -notmatch '\\build\\|\\.dart_tool\\|\\android\\build\\' }
foreach ($f in $files) {
  $rel = $f.FullName.Replace('c:\Users\nunes\Downloads\projetos\discord_app\','')
  $n = 0
  foreach ($line in Get-Content $f.FullName -ErrorAction SilentlyContinue) {
    $n++
    if ($line -match $patterns) {
      $t = $line.Trim(); if ($t.Length -gt 95) { $t = $t.Substring(0,95) }
      Write-Output "${rel}:${n}: $t"
    }
  }
}
