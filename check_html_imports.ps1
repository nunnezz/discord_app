$hits = Get-ChildItem -Path "c:\Users\nunes\Downloads\projetos\discord_app\lib" -Recurse -Include *.dart |
Select-String -Pattern "dart:html|dart:js" |
Where-Object { $_.Filename -ne 'web_activity_web.dart' }
if ($hits) {
  $hits | ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
}
else {
  Write-Output "NENHUM import de dart:html/dart:js fora de web_activity_web.dart"
}
