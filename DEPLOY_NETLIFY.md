# 🚀 Deploy na Netlify — Cord (Discord Clone)

Este guia te ajuda a configurar o deploy do seu app Flutter Web na Netlify com o Supabase corretamente.

---

## ⚠️ Problema conhecido: "Failed to decode error response"

Esse erro acontece no Flutter Web porque:

1. **O `.env` não funciona no Web** — o `flutter_dotenv` é ignorado (`kIsWeb`)
2. **As variáveis de ambiente precisam ser passadas via `--dart-define`** na hora de buildar
3. **O banco de dados do Supabase precisa estar configurado** (tabelas, RLS, storage buckets)
4. **As variáveis `SUPABASE_URL` e `SUPABASE_ANON_KEY` precisam estar no painel da Netlify**

---

## 1. Configure o banco de dados no Supabase

Acesse https://app.supabase.com, vá no seu projeto, clique em **SQL Editor** e cole todo o conteúdo do arquivo:

```
supabase_schema.sql
```

Este arquivo cria todas as tabelas necessárias: `profiles`, `servers`, `server_members`, `channels`, `messages`, `dm_conversations`, `direct_messages`, `friend_requests`, buckets de storage (`avatars`, `chat-media`), funções e triggers.

---

## 2. Pegue suas credenciais do Supabase

No painel do Supabase, vá em **Settings > API** e anote:

| Variável | Valor |
|----------|-------|
| `SUPABASE_URL` | `https://seu-projeto.supabase.co` |
| `SUPABASE_ANON_KEY` | `sb_publishable_...` (a chave pública) |

---

## 3. Configure as variáveis de ambiente na Netlify

No painel da Netlify:

1. Vá em **Site settings > Build & deploy > Environment**
2. Clique em **Edit variables**
3. Adicione estas variáveis:

| Chave | Valor |
|-------|-------|
| `SUPABASE_URL` | `https://seu-projeto.supabase.co` |
| `SUPABASE_ANON_KEY` | `sua_chave_anon_key` |
| `AGORA_APP_ID` | `seu_app_id_do_agora` (opcional, só para chamadas de voz/vídeo) |
| `AGORA_APP_CERTIFICATE` | `seu_certificado` (opcional) |

> ⚠️ Não coloque valores reais no `.env` — ele não será usado no deploy Web.

---

## 4. Build do Flutter Web com variáveis de ambiente

Para buildar localmente e testar antes de enviar para a Netlify:

```powershell
# No Windows PowerShell, dentro da pasta do projeto:
flutter build web --dart-define=SUPABASE_URL=https://seu-projeto.supabase.co --dart-define=SUPABASE_ANON_KEY=sua_chave_anon_key --dart-define=AGORA_APP_ID=seu_app_id
```

Ou crie um arquivo `build_web.bat`:

```bat
@echo off
flutter build web --dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY% --dart-define=AGORA_APP_ID=%AGORA_APP_ID%
```

---

## 5. Configurar o build na Netlify (netlify.toml)

Crie um arquivo `netlify.toml` na raiz do projeto se ainda não existir:

```toml
[build]
  command = "flutter build web --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY --dart-define=AGORA_APP_ID=$AGORA_APP_ID"
  publish = "build/web"

[build.environment]
  # As variáveis SUPABASE_URL, SUPABASE_ANON_KEY, AGORA_APP_ID devem ser definidas
  # no painel da Netlify em Site settings > Environment
```

---

## 6. Como o app lê as variáveis no Web

No Flutter Web, o `app_config.dart` lê as variáveis via `const String.fromEnvironment()`:

```dart
static String get supabaseUrl => kIsWeb
    ? const String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: _defaultSupabaseUrl,
      )
    : dotenv.env['SUPABASE_URL'] ?? _defaultSupabaseUrl;
```

Isso significa que, no Web, se `SUPABASE_URL` não for definido via `--dart-define`, o app usará o valor padrão hardcoded (que é o projeto Supabase original). Se você quiser usar um projeto diferente, deve passar a variável no build.

---

## 7. Checklist antes do deploy

- [ ] Executei o `supabase_schema.sql` no SQL Editor do Supabase?
- [ ] Adicionei `SUPABASE_URL` e `SUPABASE_ANON_KEY` nas Environment Variables da Netlify?
- [ ] O build do Flutter Web usa `--dart-define` para passar as variáveis?
- [ ] O repositório está no GitHub (já está: github.com/nunrezz/discord_app)?

---

## 8. Se ainda der erro após o deploy

1. Abra o console do navegador (F12) no site da Netlify
2. Tente fazer login e anote o erro exato que aparece no console
3. Se for CORS, verifique se o Supabase tem o domínio da Netlify nas allowed origins
4. Se for "Failed to decode error response", verifique se as variáveis de ambiente estão configuradas corretamente na Netlify

---

## Arquivos criados/modificados nesta correção

| Arquivo | O que faz |
|---------|-----------|
| `supabase_schema.sql` | Schema completo do banco de dados Supabase |
| `.env.example` | Exemplo de variáveis de ambiente (já existia) |
| `lib/services/auth_service.dart` | Tratamento de erros de rede/CORS/timeout para Flutter Web |
| `DEPLOY_NETLIFY.md` | Este guia |
| `BACKUP_AUTOMATICO.md` | Guia de backup automático (já existia) |
| `backup.ps1` | Script de backup automático (já existia) |
