Set-Location "c:\Users\nunes\Downloads\projetos\discord_app"

# WEB (navegador do PC ou CELULAR na mesma rede Wi-Fi):
# - O Flutter já serve o app na rede local (não só localhost).
#   Abra no celular:  http://192.168.1.47:8080
# - --web-hostname 0.0.0.0 faz o servidor escutar em todas as interfaces.
& "C:\Users\nunes\Downloads\flutter\bin\flutter.bat" run -d edge --web-port 8080 --web-hostname 0.0.0.0 `
  --dart-define=SUPABASE_URL="https://hcwetkdnxqeveyyurawm.supabase.co" `
  --dart-define=SUPABASE_ANON_KEY="sb_publishable_l9ux4cEv39cv3MLWfKWjPQ_15KwOEKv" `
  --dart-define=AGORA_APP_ID="bbdb563cea9b4a448ef546dfc7ee53ff"
