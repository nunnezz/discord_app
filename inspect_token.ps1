$line = (Get-Content "c:\Users\nunes\Downloads\projetos\discord_app\.env" | Where-Object { $_ -like "SUPABASE_URL=*" }) -join ""
$url = ($line -split "=",2)[1].Trim()
$keyline = (Get-Content "c:\Users\nunes\Downloads\projetos\discord_app\.env" | Where-Object { $_ -like "SUPABASE_ANON_KEY=*" }) -join ""
$key = ($keyline -split "=",2)[1].Trim()
$r = Invoke-WebRequest -Uri "$url/functions/v1/agora-token" -Method POST -Headers @{ "Authorization" = "Bearer $key"; "apikey" = $key; "Content-Type" = "application/json" } -Body '{"channelName":"x","uid":1}' -TimeoutSec 25 -UseBasicParsing
$t = ($r.Content | ConvertFrom-Json).token
$b64 = $t.Substring(4)
$pad = (4 - ($b64.Length % 4)) % 4
if ($pad -gt 0) { $b64 = $b64 + ("=" * $pad) }
$bytes = [Convert]::FromBase64String($b64)
$hex = ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
# App ID vai como STRING no formato do token Agora (length-prefixed).
# 'bbdb563cea9b4a448ef546dfc7ee53ff' em hex ASCII:
$targetHex = ''
foreach ($ch in 'bbdb563cea9b4a448ef546dfc7ee53ff'.ToCharArray()) { $targetHex += '{0:x2}' -f [byte][char]$ch }
$found = $hex.Contains($targetHex)
Write-Output "App ID bbdb563c... presente nos bytes do token? $found"
if (-not $found) {
  # procura 32 bytes consecutivos ASCII hex-charset (o app id real)
  $s = [System.Text.Encoding]::ASCII.GetString($bytes)
  # tenta achar sequência de 32 chars [0-9a-f] permitindo binário no meio? não dá.
  # alternativa: mostra a região dos primeiros 40 bytes em hex
  Write-Output "primeiros 80 bytes do token: $($hex.Substring(0,160))"
}
