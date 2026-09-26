-- Permite que o próprio usuário exclua a conta pelo app (Config → Excluir conta).
-- Rodar uma vez no Supabase: SQL Editor → New query → colar → Run.
create or replace function public.excluir_conta()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from auth.users where id = auth.uid();
$$;

revoke all on function public.excluir_conta() from public, anon;
grant execute on function public.excluir_conta() to authenticated;
