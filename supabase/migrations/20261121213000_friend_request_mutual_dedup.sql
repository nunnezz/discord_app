-- ============================================================
-- PEDIDOS DE AMIZADE MÚTUOS:
-- quando A→B e B→A existem ao mesmo tempo com status 'accepted', a lista
-- de amigos mostrava a mesma pessoa 2x. Mantemos um único pedido por par
-- (qualquer direção) e bloqueamos novos pares duplicados.
-- ============================================================

-- 1. Consolida pares duplicados: mantém o pedido mais antigo, remove o outro.
delete from public.friend_requests d
where exists (
  select 1
  from public.friend_requests k
  where k.id <> d.id
    and (
      (k.sender_id = d.sender_id and k.receiver_id = d.receiver_id)
      or (k.sender_id = d.receiver_id and k.receiver_id = d.sender_id)
    )
    and (k.created_at, k.id) < (d.created_at, d.id)
);

-- 2. Bloqueia novos pares duplicados em qualquer direção.
create unique index if not exists friend_requests_pair_unique
  on public.friend_requests (
    least(sender_id, receiver_id), greatest(sender_id, receiver_id)
  );
