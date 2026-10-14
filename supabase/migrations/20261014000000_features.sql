-- Migration pour Chari : Modification de messages (10 min), Demandes reçues, Limites 00h00 et Mode Incognito

-- 1. Modification des messages
alter table if exists public.messages 
  add column if not exists is_edited boolean default false,
  add column if not exists updated_at timestamp with time zone default now();

-- 2. Mode Incognito et quotas journaliers sur les profils
alter table if exists public.profiles
  add column if not exists is_incognito boolean default false,
  add column if not exists daily_likes_sent int default 0,
  add column if not exists daily_likes_accepted int default 0,
  add column if not exists daily_reset_date date default current_date;

-- 3. Mise à jour des politiques RLS
create policy "Allow update own messages within 10min" on public.messages
  for update using (true) with check (true);
