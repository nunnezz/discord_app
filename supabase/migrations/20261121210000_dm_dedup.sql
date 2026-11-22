-- ============================================================
-- CORREÇÃO DE CONVERSAS DUPLICADAS:
-- 1. Deduplica conversas existentes (mantém a mais antiga de cada par).
-- 2. Adiciona constraint que impede o MESMO par (qualquer ordem) duas vezes.
-- ============================================================

-- 1a. Move mensagens das duplicadas para a conversa que fica.
with dupes as (
  select id,
         row_number() over (
           partition by least(user_a, user_b), greatest(user_a, user_b)
           order by created_at asc
         ) as rn,
         least(user_a, user_b) as ua,
         greatest(user_a, user_b) as ub
  from public.dm_conversations
),
keep as (select id as keep_id, ua, ub from dupes where rn = 1)
update public.direct_messages dm
set conversation_id = k.keep_id
from dupes d
join keep k on d.ua = k.ua and d.ub = k.ub
where dm.conversation_id = d.id and d.id <> k.keep_id;

-- 1b. Exclui as conversas duplicadas (mantém a primeira de cada par).
delete from public.dm_conversations d
where exists (
  select 1
  from public.dm_conversations k
  where k.id <> d.id
    and least(k.user_a, k.user_b) = least(d.user_a, d.user_b)
    and greatest(k.user_a, k.user_b) = greatest(d.user_a, d.user_b)
    and (k.created_at, k.id) < (d.created_at, d.id)
);

-- 2. Impede que voltem a existir (ordem qualquer do par). Como UNIQUE
--    não aceita expressões, usamos um índice único funcional.
create unique index if not exists dm_conversations_pair_unique
  on public.dm_conversations (
    least(user_a, user_b), greatest(user_a, user_b)
  );
