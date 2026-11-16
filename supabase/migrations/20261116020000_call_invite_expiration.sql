alter table public.direct_messages
  add column if not exists expires_at timestamptz;

update public.direct_messages
set expires_at = now() + interval '24 hours'
where content like 'VOICE_CALL_INVITE::%'
  and expires_at is null;

create or replace function public.set_call_invite_expiration()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.content like 'VOICE_CALL_INVITE::%' then
    new.expires_at := pg_catalog.now() + interval '24 hours';
  else
    new.expires_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists direct_messages_set_call_invite_expiration
  on public.direct_messages;
create trigger direct_messages_set_call_invite_expiration
before insert on public.direct_messages
for each row
execute function public.set_call_invite_expiration();
