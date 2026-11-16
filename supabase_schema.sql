-- ================================================================================
-- SCHEMA DO SUPABASE — Cord (Discord Clone)
-- Execute este SQL no Editor SQL do seu projeto Supabase (https://app.supabase.com)
-- ================================================================================

create extension if not exists "pgcrypto";

-- ================================================================================
-- TABELA: profiles
-- ================================================================================
create table if not exists profiles (
  id uuid references auth.users not null primary key,
  username text unique not null,
  display_name text not null,
  avatar_url text,
  status_message text default 'O que você tem ouvindo?',
  bio text default '',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table profiles enable row level security;

create policy "Usuários podem ver seus próprios perfis"
  on profiles for select using (auth.uid() = id);

create policy "Usuários podem atualizar seus próprios perfis"
  on profiles for update using (auth.uid() = id);

create policy "Usuários podem inserir seu próprio perfil"
  on profiles for insert with check (auth.uid() = id);

-- ================================================================================
-- TABELA: servers
-- ================================================================================
create table if not exists servers (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  icon_text text,
  owner_id uuid references auth.users not null,
  is_public boolean default false,
  created_at timestamptz default now()
);

alter table servers enable row level security;

create policy "Qualquer um pode ver servidores públicos"
  on servers for select using (is_public = true);

create policy "Dono pode ver seus servidores"
  on servers for select using (owner_id = auth.uid());

create policy "Qualquer um autenticado pode criar servidor"
  on servers for insert with check (auth.uid() = owner_id);

create policy "Dono pode atualizar seu servidor"
  on servers for update using (owner_id = auth.uid());

-- ================================================================================
-- TABELA: server_members
-- ================================================================================
create table if not exists server_members (
  id uuid default gen_random_uuid() primary key,
  server_id uuid references servers(id) on delete cascade not null,
  user_id uuid references auth.users not null,
  joined_at timestamptz default now(),
  unique(server_id, user_id)
);

alter table server_members enable row level security;

create policy "Membros podem ver quem está no servidor"
  on server_members for select using (true);

create policy "Usuário pode entrar em servidor"
  on server_members for insert with check (auth.uid() = user_id);

-- ================================================================================
-- TABELA: channels
-- ================================================================================
create table if not exists channels (
  id uuid default gen_random_uuid() primary key,
  server_id uuid references servers(id) on delete cascade not null,
  name text not null,
  type text check (type in ('text', 'voice')) not null default 'text',
  position integer default 0,
  created_at timestamptz default now()
);

alter table channels enable row level security;

create policy "Membros podem ver canais do servidor"
  on channels for select
  using (
    exists (
      select 1 from server_members
      where server_members.server_id = channels.server_id
      and server_members.user_id = auth.uid()
    )
  );

create policy "Dono do servidor pode criar canais"
  on channels for insert
  with check (
    exists (
      select 1 from servers
      where servers.id = channels.server_id
      and servers.owner_id = auth.uid()
    )
  );

-- ================================================================================
-- TABELA: messages
-- ================================================================================
create table if not exists messages (
  id uuid default gen_random_uuid() primary key,
  server_id text not null default 'default',
  channel text not null,
  sender_id uuid references auth.users not null,
  content text,
  media_path text,
  media_type text,
  media_name text,
  created_at timestamptz default now()
);

alter table messages enable row level security;

create policy "Qualquer um autenticado pode ver mensagens"
  on messages for select using (auth.uid() is not null);

create policy "Usuário autenticado pode enviar mensagens"
  on messages for insert with check (auth.uid() = sender_id);

create index if not exists idx_messages_server_channel_created
  on messages(server_id, channel, created_at);

-- ================================================================================
-- TABELA: dm_conversations
-- ================================================================================
create table if not exists dm_conversations (
  id uuid default gen_random_uuid() primary key,
  user_a uuid references auth.users not null,
  user_b uuid references auth.users not null,
  created_at timestamptz default now(),
  unique(user_a, user_b)
);

alter table dm_conversations enable row level security;

create policy "Usuários podem ver suas próprias conversas DM"
  on dm_conversations for select
  using (user_a = auth.uid() or user_b = auth.uid());

-- ================================================================================
-- TABELA: direct_messages
-- ================================================================================
create table if not exists direct_messages (
  id uuid default gen_random_uuid() primary key,
  conversation_id uuid references dm_conversations(id) on delete cascade not null,
  sender_id uuid references auth.users not null,
  content text,
  media_path text,
  media_type text,
  media_name text,
  media_url text,
  created_at timestamptz default now(),
  expires_at timestamptz
);

alter table direct_messages enable row level security;

create policy "Participantes podem ver mensagens da conversa"
  on direct_messages for select
  using (
    exists (
      select 1 from dm_conversations
      where dm_conversations.id = direct_messages.conversation_id
      and (dm_conversations.user_a = auth.uid() or dm_conversations.user_b = auth.uid())
    )
  );

create policy "Remetente pode enviar mensagem DM"
  on direct_messages for insert with check (auth.uid() = sender_id);

create index if not exists idx_direct_messages_conversation_created
  on direct_messages(conversation_id, created_at);

-- ================================================================================
-- TABELA: friend_requests
-- ================================================================================
create table if not exists friend_requests (
  id uuid default gen_random_uuid() primary key,
  sender_id uuid references auth.users not null,
  receiver_id uuid references auth.users not null,
  status text check (status in ('pending', 'accepted', 'rejected')) default 'pending',
  created_at timestamptz default now(),
  responded_at timestamptz,
  unique(sender_id, receiver_id)
);

alter table friend_requests enable row level security;

create policy "Usuários podem ver pedidos onde estão envolvidos"
  on friend_requests for select
  using (sender_id = auth.uid() or receiver_id = auth.uid());

create policy "Usuário autenticado pode enviar pedido de amizade"
  on friend_requests for insert
  with check (auth.uid() = sender_id);

create policy "Receptor pode aceitar/rejeitar pedido"
  on friend_requests for update
  using (receiver_id = auth.uid());

-- ================================================================================
-- BUCKETS DO STORAGE
-- ================================================================================
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', true)
on conflict (id) do nothing;

-- ================================================================================
-- POLÍTICAS DO STORAGE (avatars)
-- ================================================================================
create policy "Avatar pública para leitura"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "Usuário pode fazer upload do próprio avatar"
  on storage.objects for insert
  with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "Usuário pode atualizar seu próprio avatar"
  on storage.objects for update
  using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

-- ================================================================================
-- POLÍTICAS DO STORAGE (chat-media)
-- ================================================================================
create policy "Mídia de chat pública para leitura"
  on storage.objects for select
  using (bucket_id = 'chat-media');

create policy "Usuário autenticado pode fazer upload de mídia"
  on storage.objects for insert
  with check (bucket_id = 'chat-media' and auth.uid() is not null);

-- ================================================================================
-- FUNÇÃO: get_or_create_dm_conversation
-- ================================================================================
create or replace function get_or_create_dm_conversation(other_user_id uuid)
returns uuid language plpgsql as $$
declare
  conv_id uuid;
begin
  select id into conv_id
  from dm_conversations
  where (user_a = auth.uid() and user_b = other_user_id)
     or (user_a = other_user_id and user_b = auth.uid())
  limit 1;

  if conv_id is not null then
    return conv_id;
  end if;

  insert into dm_conversations (user_a, user_b)
  values (auth.uid(), other_user_id)
  returning id into conv_id;

  return conv_id;
end;
$$;

-- ================================================================================
-- FUNÇÃO: create_server_invite
-- ================================================================================
create or replace function create_server_invite(target_server_id uuid)
returns text language plpgsql as $$
declare
  invite_code text;
begin
  invite_code := encode(gen_random_bytes(4), 'hex');
  return invite_code;
end;
$$;

-- ================================================================================
-- FUNÇÃO: join_public_server
-- ================================================================================
create or replace function join_public_server(target_server_id uuid)
returns uuid language plpgsql as $$
declare
  server_owner uuid;
begin
  select owner_id into server_owner
  from servers
  where id = target_server_id and is_public = true;

  if server_owner is null then
    raise exception 'Servidor não encontrado ou não é público';
  end if;

  insert into server_members (server_id, user_id)
  values (target_server_id, auth.uid())
  on conflict (server_id, user_id) do nothing;

  return target_server_id;
end;
$$;

-- ================================================================================
-- FUNÇÃO: join_server_with_invite
-- ================================================================================
create or replace function join_server_with_invite(invite_code text)
returns uuid language plpgsql as $$
declare
  target_server_id uuid;
begin
  target_server_id := invite_code::uuid;

  insert into server_members (server_id, user_id)
  values (target_server_id, auth.uid())
  on conflict (server_id, user_id) do nothing;

  return target_server_id;
end;
$$;

-- ================================================================================
-- TRIGGER: atualizar updated_at na tabela profiles
-- ================================================================================
create or replace function update_profiles_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trigger_update_profiles_updated_at
  before update on profiles
  for each row
  execute function update_profiles_updated_at();

-- ================================================================================
-- TRIGGER: criar perfil automaticamente quando usuário se cadastra no Supabase Auth
-- ================================================================================
create or replace function handle_new_user()
returns trigger language plpgsql as $$
begin
  insert into profiles (id, username, display_name)
  values (
    new.id,
    coalesce(split_part(new.email, '@', 1), 'usuario'),
    coalesce(split_part(new.email, '@', 1), 'Usuário')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function handle_new_user();

-- ================================================================================
-- FIM DO SCHEMA
-- ================================================================================