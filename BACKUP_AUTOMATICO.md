# ☁️ Backup Automático na Nuvem — Cord (Discord Clone)

Este projeto já vem com:

| Arquivo | Função |
|---------|--------|
| `.gitignore` | Ignora build, `.dart_tool/`, `.env` (credenciais), etc. |
| `backup.ps1` | Script PowerShell que faz `git add`, `commit` e `push` automaticamente |
| `BACKUP_AUTOMATICO.md` | Este guia |

---

## 1. Pré-requisito: instalar o Git

Se ainda não tiver o Git instalado no Windows:

1. Baixe em: https://git-scm.com/download/win
2. Instale com as opções padrão.
3. Reinicie o terminal (PowerShell ou CMD) após a instalação.

Verifique com:
```powershell
git --version
```

---

## 2. Criar repositório privado no GitHub (ou GitLab/Bitbucket)

1. Acesse https://github.com (ou gitlab.com / bitbucket.org)
2. Crie um repositório **privado** chamado `cord_app` (ou `discord_app`)
3. **Não inicialize com README, .gitignore nem LICENSE** (o projeto já tem)
4. Copie a URL do repositório, ex: `https://github.com/seu-usuario/cord_app.git`

---

## 3. Conectar o projeto local ao repositório remoto

No PowerShell, dentro da pasta do projeto:

```powershell
cd "C:\Users\nunes\Downloads\projetos\discord_app"
git init
git add .
git commit -m "commit inicial: Cord - clone do Discord com Supabase"
git branch -M main
git remote add origin https://github.com/seu-usuario/cord_app.git
git push -u origin main
```

> ⚠️ **O arquivo `.env` NÃO será enviado**, porque está no `.gitignore`. Suas credenciais do Supabase e Agora ficam seguras localmente.

---

## 4. Automatizar o backup com o Agendador de Tarefas (Windows)

Para rodar o `backup.ps1` automaticamente (ex: todos os dias às 22h):

1. Abra o **Agendador de Tarefas** (`taskschd.msc`)
2. Clique em **Criar Tarefa Básica...**
3. Nome: `Backup Cord App`
4. Gatilho: **Diário**, às 22:00 (ou escolha outro horário)
5. Ação: **Iniciar um programa**
   - Programa/script: `powershell.exe`
   - Adicionar argumentos:
     ```
     -ExecutionPolicy Bypass -File "C:\Users\nunes\Downloads\projetos\discord_app\backup.ps1"
     ```
6. Concluir.

Pronto! Todas as noites (ou no horário escolhido), o Windows fará commit e push automático das mudanças para a nuvem.

---

## 5. Restaurar o projeto em outro computador

```powershell
git clone https://github.com/seu-usuario/cord_app.git
cd cord_app
# Copie seu arquivo .env local para dentro da pasta (não está no Git)
flutter pub get
flutter run
```

---

## 6. Segurança importante

- Nunca commite o arquivo `.env` (ele contém chaves do Supabase e Agora).
- Mantenha seu repositório como **privado**.
- Se precisar compartilhar variáveis de ambiente com alguém, crie um `.env.example` com valores fictícios e comente no README.
