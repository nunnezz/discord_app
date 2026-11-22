# Servidor local do Cord aberto para TODOS os dispositivos da rede.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File serve_lan.ps1
Set-Location "c:\Users\nunes\Downloads\projetos\discord_app\build\web"
Write-Output "Servindo build/web para toda a rede em http://192.168.1.47:8080"
& python -m http.server 8080 --bind 0.0.0.0
