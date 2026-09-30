-- Backup na nuvem do LBO Finanças: uma linha por usuário com todos os dados dele.
-- Rodar uma vez no Supabase: SQL Editor → New query → colar → Run.
create table if not exists public.backups (
  user_id uuid primary key references auth.users(id) on delete cascade,
  dados jsonb not null,
  atualizado_em timestamptz not null default now()
);

alter table public.backups enable row level security;

drop policy if exists "backup: dono le" on public.backups;
drop policy if exists "backup: dono cria" on public.backups;
drop policy if exists "backup: dono atualiza" on public.backups;

create policy "backup: dono le" on public.backups
  for select to authenticated using (auth.uid() = user_id);
create policy "backup: dono cria" on public.backups
  for insert to authenticated with check (auth.uid() = user_id);
create policy "backup: dono atualiza" on public.backups
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, insert, update on public.backups to authenticated;
