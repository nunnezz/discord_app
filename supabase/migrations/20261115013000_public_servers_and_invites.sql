alter table public.servers
  add column if not exists is_public boolean not null default false;

create table if not exists public.server_invites (
  id uuid primary key default gen_random_uuid(),
  server_id uuid not null references public.servers(id) on delete cascade,
  code text not null unique,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create index if not exists server_invites_server_id_idx
  on public.server_invites (server_id);

alter table public.server_invites enable row level security;

drop policy if exists "Ver servidores dos quais sou membro" on public.servers;
drop policy if exists "servers_read_all" on public.servers;
drop policy if exists "servers_select_members" on public.servers;
drop policy if exists "servers_read_public_or_member" on public.servers;
drop policy if exists "Ver servidores públicos ou dos quais sou membro" on public.servers;
create policy "Ver servidores públicos ou dos quais sou membro"
on public.servers
for select
to authenticated
using (is_public or public.is_member_of_server(id));

drop policy if exists "Entrar em um servidor (como eu mesmo)" on public.server_members;
drop policy if exists "server_members_insert_self" on public.server_members;

drop policy if exists "Usuários logados leem mensagens" on public.messages;
drop policy if exists "messages_read_all" on public.messages;
drop policy if exists "messages_read_member_servers" on public.messages;
drop policy if exists "Membros leem mensagens" on public.messages;
create policy "Membros leem mensagens"
on public.messages
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

drop policy if exists "Usuários logados enviam mensagens como si mesmos" on public.messages;
drop policy if exists "messages_insert_self" on public.messages;
drop policy if exists "messages_insert_member_self" on public.messages;
drop policy if exists "Membros enviam mensagens como si mesmos" on public.messages;
create policy "Membros enviam mensagens como si mesmos"
on public.messages
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

  insert into public.server_invites (
    server_id,
    code,
    created_by,
    expires_at
  )
  values (
    target_server_id,
    invite_code,
    auth.uid(),
    now() + interval '7 days'
  );

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

  select s.is_public
    into is_server_public
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

  select i.server_id
    into invited_server_id
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

revoke all on function public.create_server_invite(uuid) from public;
revoke all on function public.join_public_server(uuid) from public;
revoke all on function public.join_server_with_invite(text) from public;

grant execute on function public.create_server_invite(uuid) to authenticated;
grant execute on function public.join_public_server(uuid) to authenticated;
grant execute on function public.join_server_with_invite(text) to authenticated;
