# ==============================================================================
# BACKUP AUTOMÁTICO — Cord (Discord Clone)
# Faz commit e push de todas as mudanças para o repositório remoto (GitHub/GitLab)
# ==============================================================================

$ErrorActionPreference = "Stop"

# Diretório do projeto (ajuste se mover a pasta)
$projectDir = "C:\Users\nunes\Downloads\projetos\discord_app"

# Nome da branch principal
$branch = "main"

# Mensagem de commit automático com data/hora
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$commitMessage = "backup automático: $timestamp"

Write-Host "=== Iniciando backup automático ($timestamp) ===" -ForegroundColor Cyan

Set-Location $projectDir

# Verifica se é um repositório Git
if (-not (Test-Path ".git")) {
    Write-Host "ERRO: este diretório não é um repositório Git. Rode 'git init' primeiro." -ForegroundColor Red
    exit 1
}

# Adiciona todos os arquivos (respeitando o .gitignore)
git add .

# Verifica se há mudanças para commitar
$status = git status --porcelain
if ($null -eq $status -or $status.Trim() -eq "") {
    Write-Host "Nenhuma mudança detectada. Nada para fazer backup." -ForegroundColor Green
    exit 0
}

# Commit
git commit -m "$commitMessage"

# Push para o remoto
try {
    git push origin $branch
    Write-Host "Backup concluído com sucesso! (`$timestamp)" -ForegroundColor Green
}
catch {
    Write-Host "ERRO ao fazer push: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Dica: verifique se o remote 'origin' está configurado e se você tem permissão de push." -ForegroundColor Yellow
    exit 1
}