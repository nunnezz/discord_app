create extension if not exists pg_net with schema extensions;

alter table public.messages
  add column if not exists media_path text,
  add column if not exists media_type text,
  add column if not exists media_name text;

alter table public.direct_messages
  add column if not exists media_path text,
  add column if not exists media_type text,
  add column if not exists media_name text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'messages_media_metadata_check'
  ) then
    alter table public.messages
      add constraint messages_media_metadata_check
      check (
        (media_path is null and media_type is null and media_name is null)
        or (
          media_path is not null
          and media_type in ('image', 'video')
          and media_name is not null
          and split_part(media_path, '/', 1) = sender_id::text
        )
      );
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'direct_messages_media_metadata_check'
  ) then
    alter table public.direct_messages
      add constraint direct_messages_media_metadata_check
      check (
        (media_path is null and media_type is null and media_name is null)
        or (
          media_path is not null
          and media_type in ('image', 'video')
          and media_name is not null
          and split_part(media_path, '/', 1) = sender_id::text
        )
      );
  end if;
end;
$$;

create index if not exists messages_retention_created_at_idx
  on public.messages (created_at);
create index if not exists direct_messages_retention_created_at_idx
  on public.direct_messages (created_at);

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'chat-media',
  'chat-media',
  false,
  20971520,
  array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'video/mp4',
    'video/webm',
    'video/quicktime'
  ]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "chat_media_insert_own" on storage.objects;
create policy "chat_media_insert_own" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'chat-media'
  and (storage.foldername(name))[1] = auth.uid()::text
  and (metadata->>'mimetype') is not null
  and (
    (
      (metadata->>'mimetype') like 'image/%'
      and coalesce(
        nullif(metadata->>'size', ''),
        nullif(metadata->>'contentLength', '')
      )::bigint <= 5242880
    )
    or (
      (metadata->>'mimetype') like 'video/%'
      and coalesce(
        nullif(metadata->>'size', ''),
        nullif(metadata->>'contentLength', '')
      )::bigint <= 20971520
    )
  )
);

drop policy if exists "chat_media_select_message_participants" on storage.objects;
create policy "chat_media_select_message_participants" on storage.objects
for select to authenticated
using (
  bucket_id = 'chat-media'
  and (
    exists (
      select 1
      from public.messages m
      where m.media_path = name
    )
    or exists (
      select 1
      from public.direct_messages dm
      where dm.media_path = name
    )
  )
);

drop policy if exists "chat_media_delete_own" on storage.objects;
create policy "chat_media_delete_own" on storage.objects
for delete to authenticated
using (
  bucket_id = 'chat-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);

do $$
begin
  if not exists (
    select 1
    from vault.decrypted_secrets
    where name = 'chat_retention_cron_secret'
  ) then
    raise exception
      'Create Vault secret chat_retention_cron_secret before applying this migration.';
  end if;
end;
$$;

select vault.create_secret(
  'https://hcwetkdnxqeveyyurawm.supabase.co',
  'chat_retention_project_url'
)
where not exists (
  select 1
  from vault.decrypted_secrets
  where name = 'chat_retention_project_url'
);

do $$
declare
  existing_job record;
begin
  for existing_job in
    select jobid
    from cron.job
    where jobname = 'cleanup-chat-retention'
  loop
    perform cron.unschedule(existing_job.jobid);
  end loop;

  perform cron.schedule(
    'cleanup-chat-retention',
    '0 4 * * *',
    $job$
      select net.http_post(
        url := (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'chat_retention_project_url'
        ) || '/functions/v1/cleanup-chat-retention',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', (
            select decrypted_secret
            from vault.decrypted_secrets
            where name = 'chat_retention_cron_secret'
          )
        ),
        body := jsonb_build_object('scheduled_at', now())
      );
    $job$
  );
end;
$$;
