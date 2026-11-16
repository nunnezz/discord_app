# Cord app

Aplicativo tipo Discord em Flutter com autenticação, perfis, amigos, DMs, servidores, canais e chamadas de voz usando Supabase + Agora.

## Requisitos

- Flutter SDK instalado e no PATH
- Projeto Supabase criado
- Conta Agora com App ID e App Certificate
- Node/npm opcional para Supabase CLI

## Configuração rápida

1. Copie o arquivo [.env.example](.env.example) para `.env`.
2. Atualize as variáveis do projeto:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `AGORA_APP_ID`
3. Execute no terminal:

   ```bash
   flutter pub get
   flutter run
   ```

## Banco de dados

No painel do Supabase, abra SQL Editor e execute o script em [supabase/schema.sql](supabase/schema.sql).

Esse arquivo cria as tabelas necessárias para:

- `profiles`
- `servers`
- `server_members`
- `channels`
- `messages`
- `friend_requests`
- `dm_conversations`
- `direct_messages`
- `server_invites`

Além disso, ele também cria triggers e políticas iniciais para o fluxo do app.

### Projeto Supabase já existente

Não execute o schema completo em um projeto que já tem tabelas ou dados. Para adicionar servidores públicos e convites a uma instalação existente, execute somente a migration [20261115013000_public_servers_and_invites.sql](supabase/migrations/20261115013000_public_servers_and_invites.sql) no SQL Editor.

Servidores novos são privados por padrão. O dono pode alterar a visibilidade nas opções do servidor. Servidores públicos aparecem na descoberta e usuários autenticados podem entrar; servidores privados exigem um código de convite, válido por 7 dias. Membros podem gerar um código pelo menu do servidor e compartilhá-lo; quem recebe pode colar o código em “Entrar com convite”.

Para fotos de perfil, execute a migration [20261115223000_profile_avatar_storage.sql](supabase/migrations/20261115223000_profile_avatar_storage.sql) em um projeto existente. Ela cria o bucket público `avatars` (JPG, PNG e WEBP, até 5 MB) e limita o envio/alteração à pasta do próprio usuário. Instalações novas recebem essa configuração pelo `schema.sql`.

### Mídia e expiração do chat

O chat aceita fotos JPG/PNG/WEBP de até 5 MB e vídeos MP4/WEBM/MOV de até 20 MB. Os arquivos ficam no bucket privado `chat-media`; apenas participantes da conversa/canal podem obter links temporários. Mensagens com mídia têm o arquivo removido após 3 meses (a legenda continua até completar 6 meses); mensagens escritas e o histórico existente expiram após 6 meses.

Em um projeto existente, configure um segredo aleatório `CHAT_RETENTION_CRON_SECRET` tanto nas secrets das Edge Functions quanto no Supabase Vault com o nome `chat_retention_cron_secret`. Depois faça deploy de `cleanup-chat-retention` com JWT verification desabilitado (a função valida o segredo dedicado no header), e execute a migration `20261116010000_chat_media_and_retention.sql`. Ela configura o bucket privado e agenda a limpeza diária. Nunca use a chave `service_role` como esse segredo.

## Edge Function de token do Agora

A função está em [supabase/functions/agora-token/index.ts](supabase/functions/agora-token/index.ts).

No painel do Supabase, configure as variáveis de ambiente:

- `AGORA_APP_ID`
- `AGORA_APP_CERTIFICATE`

Depois faça deploy dela:

```bash
npx supabase functions deploy agora-token
```

## Deploy no Netlify

Conecte o repositório GitHub ao site `https://cord-ap.netlify.app`. O arquivo `netlify.toml` configura o build e publica `build/web`; o script instala uma versão fixa do Flutter e compila o app.

No painel do Netlify, configure `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `AGORA_APP_ID` em **Site configuration → Environment variables**. O `AGORA_APP_ID` deve ser o mesmo configurado para a Edge Function no Supabase. Esses valores são incluídos no app web e ficam visíveis no navegador; use somente valores públicos. Não configure o certificado do Agora nem uma chave `service_role` do Supabase no build do cliente. O certificado do Agora deve ficar apenas como segredo da Edge Function no Supabase.

Depois de salvar as variáveis, faça commit e push para a branch conectada ao site para iniciar o deploy automático. O arquivo `.env` não deve ser enviado ao GitHub.

Para um build local destinado ao Netlify Drop, passe somente as variáveis públicas com `--dart-define` e remova `build/web/assets/.env` antes do upload. Nunca inclua o certificado do Agora ou uma chave `service_role` no app web.

## Observações

- O projeto já usa uma URL e anon key pública do Supabase por padrão, mas você deve manter `.env` localmente com os valores do seu projeto.
- A parte de chamada de voz precisa do App ID e do App Certificate reais do Agora.
- O schema inicial foi pensado para funcionar como base do protótipo; para produção, revise as políticas de segurança do RLS.
