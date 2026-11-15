-- Schema base para o Cord.
-- Ajuste esta estrutura no Supabase SQL editor e execute ela antes de rodar o app.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  display_name text not null default '',
  avatar_url text,
  status_message text not null default 'O que você tem ouvido?',
  bio text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.servers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) > 0),
  icon_text text,
  owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  is_public boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.server_members (
  server_id uuid not null references public.servers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (server_id, user_id)
);

create table if not exists public.server_invites (
  id uuid primary key default gen_random_uuid(),
  server_id uuid not null references public.servers(id) on delete cascade,
  code text not null unique,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create table if not exists public.channels (
  id uuid primary key default gen_random_uuid(),
  server_id uuid not null references public.servers(id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  type text not null check (type in ('text', 'voice')) default 'text',
  position integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  channel text not null,
  server_id text not null default 'default',
  sender_id uuid not null references public.profiles(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('pending', 'accepted', 'rejected')) default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (sender_id, receiver_id)
);

create table if not exists public.dm_conversations (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_a, user_b)
);

create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.dm_conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_profiles_username on public.profiles (username);
create index if not exists idx_messages_server_channel on public.messages (server_id, channel, created_at);
create index if not exists idx_channels_server_position on public.channels (server_id, position);
create index if not exists idx_friend_requests_receiver on public.friend_requests (receiver_id, status);
create index if not exists idx_dm_conversations_users on public.dm_conversations (user_a, user_b);
create index if not exists server_invites_server_id_idx on public.server_invites (server_id);

create or replace function public.is_member_of_server(check_server_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.server_members
    where server_id = check_server_id
      and user_id = auth.uid()
  );
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', lower(split_part(new.email, '@', 1))),
    coalesce(new.raw_user_meta_data->>'display_name', lower(split_part(new.email, '@', 1)))
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

create or replace function public.handle_new_server()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.server_members (server_id, user_id)
  values (new.id, new.owner_id)
  on conflict do nothing;

  insert into public.channels (server_id, name, type, position)
  values
    (new.id, 'geral', 'text', 0),
    (new.id, 'Sala de Voz', 'voice', 1);

  return new;
end;
$$;

create or replace function public.create_server_invite(target_server_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  invite_code text;
begin
  if auth.uid() is null or not public.is_member_of_server(target_server_id) then
    raise exception 'Você precisa ser membro do servidor para criar um convite.'
      using errcode = '42501';
  end if;

  invite_code := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');

  insert into public.server_invites (server_id, code, created_by, expires_at)
  values (target_server_id, invite_code, auth.uid(), now() + interval '7 days');

  return invite_code;
end;
$$;

create or replace function public.join_public_server(target_server_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  is_server_public boolean;
begin
  if auth.uid() is null then
    raise exception 'É necessário entrar na conta para participar de um servidor.'
      using errcode = '42501';
  end if;

  select s.is_public into is_server_public
  from public.servers s
  where s.id = target_server_id;

  if not found or not is_server_public then
    raise exception 'Servidor público não encontrado.'
      using errcode = 'P0002';
  end if;

  insert into public.server_members (server_id, user_id)
  values (target_server_id, auth.uid())
  on conflict (server_id, user_id) do nothing;

  return target_server_id;
end;
$$;

create or replace function public.join_server_with_invite(invite_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  invited_server_id uuid;
begin
  if auth.uid() is null then
    raise exception 'É necessário entrar na conta para usar um convite.'
      using errcode = '42501';
  end if;

  select i.server_id into invited_server_id
  from public.server_invites i
  where i.code = trim(invite_code)
    and i.expires_at > now();

  if invited_server_id is null then
    raise exception 'Convite inválido ou expirado.'
      using errcode = 'P0002';
  end if;

  insert into public.server_members (server_id, user_id)
  values (invited_server_id, auth.uid())
  on conflict (server_id, user_id) do nothing;

  return invited_server_id;
end;
$$;

create or replace function public.get_or_create_dm_conversation(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  conversation_id uuid;
begin
  select id into conversation_id
  from public.dm_conversations
  where (
    (user_a = auth.uid() and user_b = other_user_id)
    or (user_a = other_user_id and user_b = auth.uid())
  );

  if conversation_id is null then
    insert into public.dm_conversations (user_a, user_b)
    values (least(auth.uid(), other_user_id), greatest(auth.uid(), other_user_id))
    returning id into conversation_id;
  end if;

  return conversation_id;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

drop trigger if exists on_server_created on public.servers;
create trigger on_server_created
after insert on public.servers
for each row execute procedure public.handle_new_server();

alter table public.profiles enable row level security;
alter table public.servers enable row level security;
alter table public.server_members enable row level security;
alter table public.server_invites enable row level security;
alter table public.channels enable row level security;
alter table public.messages enable row level security;
alter table public.friend_requests enable row level security;
alter table public.dm_conversations enable row level security;
alter table public.direct_messages enable row level security;

create policy "profiles_read" on public.profiles
for select
using (auth.role() = 'authenticated');

create policy "profiles_insert_self" on public.profiles
for insert
with check (auth.uid() = id);

create policy "profiles_update_self" on public.profiles
for update
using (auth.uid() = id)
with check (auth.uid() = id);

create policy "servers_read_public_or_member" on public.servers
for select
to authenticated
using (is_public or public.is_member_of_server(id));

create policy "servers_insert_own" on public.servers
for insert
with check (auth.uid() = owner_id);

create policy "servers_update_owner" on public.servers
for update
using (auth.uid() = owner_id)
with check (auth.uid() = owner_id);

create policy "server_members_read_member_servers" on public.server_members
for select
to authenticated
using (public.is_member_of_server(server_id));

create policy "channels_read_member_servers" on public.channels
for select
to authenticated
using (public.is_member_of_server(server_id));

create policy "channels_insert_for_owned_server" on public.channels
for insert
with check (exists (
  select 1
  from public.servers s
  where s.id = server_id and s.owner_id = auth.uid()
));

create policy "messages_read_member_servers" on public.messages
for select
to authenticated
using (
  case
    when server_id = 'default' then true
    when server_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then public.is_member_of_server(server_id::uuid)
    else false
  end
);

create policy "messages_insert_member_self" on public.messages
for insert
to authenticated
with check (
  auth.uid() = sender_id
  and case
    when server_id = 'default' then true
    when server_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then public.is_member_of_server(server_id::uuid)
    else false
  end
);

create policy "friend_requests_read_self" on public.friend_requests
for select
using (
  auth.uid() = sender_id or auth.uid() = receiver_id
);

create policy "friend_requests_insert_self" on public.friend_requests
for insert
with check (auth.uid() = sender_id);

create policy "friend_requests_update_self" on public.friend_requests
for update
using (
  auth.uid() = sender_id or auth.uid() = receiver_id
)
with check (
  auth.uid() = sender_id or auth.uid() = receiver_id
);

create policy "dm_conversations_read_self" on public.dm_conversations
for select
using (
  auth.uid() = user_a or auth.uid() = user_b
);

create policy "dm_conversations_insert_self" on public.dm_conversations
for insert
with check (
  auth.uid() = user_a or auth.uid() = user_b
);

create policy "direct_messages_read_self" on public.direct_messages
for select
using (
  exists (
    select 1
    from public.dm_conversations dc
    where dc.id = conversation_id and (dc.user_a = auth.uid() or dc.user_b = auth.uid())
  )
);

create policy "direct_messages_insert_self" on public.direct_messages
for insert
with check (auth.uid() = sender_id);

revoke all on function public.create_server_invite(uuid) from public;
revoke all on function public.join_public_server(uuid) from public;
revoke all on function public.join_server_with_invite(text) from public;

grant execute on function public.create_server_invite(uuid) to authenticated;
grant execute on function public.join_public_server(uuid) to authenticated;
grant execute on function public.join_server_with_invite(text) to authenticated;
