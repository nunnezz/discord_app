-- ============================================================
-- GESTÃO DE CANAIS: renomear e excluir canais pelo dono do servidor
-- (o INSERT já tinha política "channels_insert_for_owned_server";
--  aqui adicionamos UPDATE e DELETE com a mesma regra de propriedade)
-- ============================================================

create policy "channels_update_owned_server" on public.channels
for update
to authenticated
using (exists (
  select 1
  from public.servers s
  where s.id = server_id and s.owner_id = auth.uid()
))
with check (exists (
  select 1
  from public.servers s
  where s.id = server_id and s.owner_id = auth.uid()
));

create policy "channels_delete_owned_server" on public.channels
for delete
to authenticated
using (exists (
  select 1
  from public.servers s
  where s.id = server_id and s.owner_id = auth.uid()
));
