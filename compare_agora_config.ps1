# Compara o hash dos SEUS valores do console Agora com o hash reportado
# pela Edge Function - sem nunca imprimir os segredos.
# Uso: powershell -File compare_agora_config.ps1 <appIdDoConsole> <certDoConsole>
param(
  [Parameter(Mandatory = $true)][string]$AppIdConsole,
  [Parameter(Mandatory = $true)][string]$CertConsole
)
$AppIdConsole = $AppIdConsole.Trim()
$CertConsole = $CertConsole.Trim()
$sha = [System.Security.Cryptography.SHA256]::Create()
function Hash16($v) {
  $h = ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($v)) | ForEach-Object { $_.ToString('x2') }) -join ''
  return $h.Substring(0, 16)
}

function LocalEnvValue($name) {
  $l = (Get-Content "c:\Users\nunes\Downloads\projetos\discord_app\.env" | Where-Object { $_ -like "$name=*" }) -join ""
  return ($l -split "=", 2)[1].Trim()
}

$url = (LocalEnvValue 'SUPABASE_URL')
$key = (LocalEnvValue 'SUPABASE_ANON_KEY')
$r = Invoke-WebRequest -Uri "$url/functions/v1/agora-token" -Method POST -Headers @{ "Authorization" = "Bearer $key"; "apikey" = $key; "Content-Type" = "application/json" } -Body '{"channelName":"x","uid":1}' -TimeoutSec 25 -UseBasicParsing
$data = $r.Content | ConvertFrom-Json

$appIdLocal = LocalEnvValue 'AGORA_APP_ID'
$hLocal = Hash16 $appIdLocal
$hConsoleApp = Hash16 $AppIdConsole
$hServerApp = $data.diag.appIdHash
$hConsoleCert = Hash16 $CertConsole
$hServerCert = $data.diag.certHash

Write-Output "=== HASHES (16 hex) ==="
Write-Output "App ID  local (.env):  $hLocal"
Write-Output "App ID  console:       $hConsoleApp"
Write-Output "App ID  edge function: $hServerApp"
Write-Output "Cert    console:       $hConsoleCert"
Write-Output "Cert    edge function: $hServerCert (len server: $($data.diag.certLen); len console: $($CertConsole.Length))"

Write-Output "=== VEREDICTO ==="
$aiOk = ($hLocal -eq $hServerApp) -and ($hConsoleApp -eq $hServerApp)
Write-Output "App ID todos iguais? $aiOk"
$certOk = ($hConsoleCert -eq $hServerCert)
Write-Output "Certificado console == servidor? $certOk"
if (-not $certOk) {
  Write-Output ">>> CERTIFICADO DO SECRET DIFERE DO CONSOLE. Corrija com:"
  Write-Output ">>>   supabase secrets set AGORA_APP_CERTIFICATE=$CertConsole"
  Write-Output ">>> (depois saia e entre de novo na call no tablet - sem rebuild)"
}
if (-not $aiOk) {
  Write-Output ">>> APP ID difere. Corrija o .env (APK) e o secret:"
  Write-Output ">>>   AGORA_APP_ID=$AppIdConsole no .env; sync_env.ps1; rebuild APK"
  Write-Output ">>>   supabase secrets set AGORA_APP_ID=$AppIdConsole"
}
