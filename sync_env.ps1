# ============================================================
# sync_env.ps1 — mantém assets/env.txt igual ao .env
# (o aapt do Android exclui dotfiles, então o APK usa a cópia)
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File sync_env.ps1
# ============================================================
Set-Location $PSScriptRoot
Copy-Item ".env" "assets\env.txt" -Force
Write-Output "assets/env.txt sincronizado com .env"
