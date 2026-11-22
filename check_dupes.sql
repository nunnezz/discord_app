-- Diagnóstico remoto: conversas duplicadas por par?
select least(user_a, user_b)::text as par_a, greatest(user_a, user_b)::text as par_b, count(*) as n
from public.dm_conversations
group by 1, 2
having count(*) > 1;
