# ==============================================================================
# BUILD LOCAL PARA TESTAR CHAMADA DE VOZ/VÍDEO NO LOCALHOST
# ==============================================================================
#
# ⚠️  ABRA ESTE ARQUIVO E SUBSTITUA "SEU_AGORA_APP_ID" PELO SEU APP ID REAL
#     (você pega em https://console.agora.io > seu projeto > App ID)
#
# ==============================================================================

$ErrorActionPreference = "Stop"

# --- Configure aqui o seu App ID do Agora ---
$agoraAppId = "bbdb563cea9b4a448ef546dfc7ee53ff"

# --- Suas credenciais do Supabase (já configuradas) ---
$supabaseUrl = "https://hcwetkdnxqeveyyurawm.supabase.co"
$supabaseAnonKey = "sb_publishable_l9ux4cEv39cv3MLWfKWjPQ_15KwOEKv"

if ($agoraAppId -eq "SEU_AGORA_APP_ID" -or [string]::IsNullOrWhiteSpace($agoraAppId)) {
    Write-Host "ERRO: você precisa editar este arquivo e colocar o AGORA_APP_ID real!" -ForegroundColor Red
    Write-Host "Abra o arquivo build_local.ps1 e troque 'SEU_AGORA_APP_ID' pelo seu ID do Agora." -ForegroundColor Yellow
    exit 1
}

Write-Host "=== Iniciando build local do Flutter Web ===" -ForegroundColor Cyan
Write-Host "Supabase URL: $supabaseUrl"
Write-Host "Agora App ID: $agoraAppId"
Write-Host ""

Set-Location "C:\Users\nunes\Downloads\projetos\discord_app"

flutter build web `
  --dart-define=SUPABASE_URL="$supabaseUrl" `
  --dart-define=SUPABASE_ANON_KEY="$supabaseAnonKey" `
  --dart-define=AGORA_APP_ID="$agoraAppId"

Write-Host ""
Write-Host "=== Build concluída com sucesso! ===" -ForegroundColor Green
Write-Host "Arquivos prontos em: C:\Users\nunes\Downloads\projetos\discord_app\build\web/"
Write-Host ""
Write-Host "Para testar localmente, rode no terminal:"
Write-Host "  cd ""C:\Users\nunes\Downloads\projetos\discord_app\build\web"""
Write-Host "  python -m http.server 8000"
Write-Host ""
Write-Host "Depois abra o navegador em: http://localhost:8000"