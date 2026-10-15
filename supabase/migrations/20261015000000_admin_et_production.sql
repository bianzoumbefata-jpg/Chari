-- =====================================================================
-- Chari : Espace administrateur + validation des selfies + mise en production
-- A executer UNE FOIS dans Supabase > SQL Editor (script idempotent :
-- il peut etre relance sans risque).
-- Administrateur unique : bianzoumbe.fata@gmail.com (connexion Google)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Colonnes manquantes (certaines migrations precedentes n'avaient
--    jamais ete appliquees : avatar_url, is_incognito, is_edited...)
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists avatar_url text,
  add column if not exists is_incognito boolean default false,
  add column if not exists daily_likes_sent int default 0,
  add column if not exists daily_likes_accepted int default 0,
  add column if not exists daily_reset_date date default current_date,
  add column if not exists verification_selfie_url text,
  add column if not exists selfie_status text not null default 'pending',
  add column if not exists selfie_reviewed_at timestamptz,
  add column if not exists selfie_reject_reason text;

alter table public.profiles drop constraint if exists profiles_selfie_status_check;
alter table public.profiles
  add constraint profiles_selfie_status_check
  check (selfie_status in ('pending', 'approved', 'rejected'));

alter table public.messages
  add column if not exists is_edited boolean default false,
  add column if not exists updated_at timestamptz default now();

create index if not exists messages_sender_idx on public.messages (sender_id);
create index if not exists messages_receiver_idx on public.messages (receiver_id);
create index if not exists profiles_selfie_status_idx on public.profiles (selfie_status);

-- ---------------------------------------------------------------------
-- 2. Qui est administrateur ? (verification cote serveur)
--    - e-mail du jeton = bianzoumbe.fata@gmail.com
--    - session ouverte via Google (OAuth), pas par mot de passe
--    - le compte possede bien une identite Google avec cet e-mail
-- ---------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(lower(auth.jwt() ->> 'email'), '') = 'bianzoumbe.fata@gmail.com'
    and exists (
      select 1
      from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) as a
      where a ->> 'method' = 'oauth'
    )
    and exists (
      select 1
      from auth.identities i
      where i.user_id = auth.uid()
        and i.provider = 'google'
        and lower(i.identity_data ->> 'email') = 'bianzoumbe.fata@gmail.com'
    );
$$;

grant execute on function public.is_admin() to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Seul l'administrateur peut valider / refuser un selfie.
--    Un membre qui change son selfie repasse automatiquement "en attente".
-- ---------------------------------------------------------------------
create or replace function public.protect_selfie_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.is_admin() then
    if tg_op = 'INSERT' or new.selfie_status is distinct from old.selfie_status then
      new.selfie_reviewed_at := case when new.selfie_status = 'pending' then null else now() end;
    end if;
    new.is_verified := (new.selfie_status = 'approved');
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.selfie_status := 'pending';
    new.selfie_reviewed_at := null;
    new.selfie_reject_reason := null;
  elsif new.verification_selfie_url is distinct from old.verification_selfie_url then
    new.selfie_status := 'pending';
    new.selfie_reviewed_at := null;
    new.selfie_reject_reason := null;
  else
    new.selfie_status := old.selfie_status;
    new.selfie_reviewed_at := old.selfie_reviewed_at;
    new.selfie_reject_reason := old.selfie_reject_reason;
  end if;
  new.is_verified := (new.selfie_status = 'approved');
  return new;
end;
$$;

drop trigger if exists trg_protect_selfie_review on public.profiles;
create trigger trg_protect_selfie_review
  before insert or update on public.profiles
  for each row execute function public.protect_selfie_review();

-- ---------------------------------------------------------------------
-- 4. Actions administrateur (refusees a tout autre compte)
-- ---------------------------------------------------------------------
create or replace function public.admin_review_selfie(
  p_user_id uuid,
  p_status text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Acces refuse' using errcode = '42501';
  end if;
  if p_status not in ('pending', 'approved', 'rejected') then
    raise exception 'Statut invalide : %', p_status;
  end if;
  update public.profiles
     set selfie_status = p_status,
         selfie_reject_reason = case when p_status = 'rejected' then nullif(trim(p_reason), '') else null end
   where id = p_user_id;
end;
$$;

create or replace function public.admin_delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Acces refuse' using errcode = '42501';
  end if;
  delete from public.messages where sender_id = p_user_id or receiver_id = p_user_id;
  delete from public.likes where sender_id = p_user_id or receiver_id = p_user_id;
  delete from public.user_blocks where user_id = p_user_id or blocked_id = p_user_id;
  delete from public.user_photos where user_id = p_user_id;
  delete from public.profiles where id = p_user_id;
  -- Supprime aussi le compte de connexion Google s'il existe
  begin
    delete from auth.users where id = p_user_id;
  exception when others then
    null;
  end;
end;
$$;

revoke execute on function public.admin_review_selfie(uuid, text, text) from public, anon;
revoke execute on function public.admin_delete_user(uuid) from public, anon;
grant execute on function public.admin_review_selfie(uuid, text, text) to authenticated;
grant execute on function public.admin_delete_user(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Securite : avant ce script, N'IMPORTE QUI pouvait supprimer des
--    profils et lire/supprimer tous les avis. On restreint a l'admin.
-- ---------------------------------------------------------------------
drop policy if exists "Allow delete profiles" on public.profiles;
drop policy if exists "Admin delete profiles" on public.profiles;
create policy "Admin delete profiles" on public.profiles
  for delete to authenticated using (public.is_admin());

drop policy if exists "Allow all feedbacks" on public.feedbacks;
drop policy if exists "Anyone can send feedback" on public.feedbacks;
drop policy if exists "Admin reads feedbacks" on public.feedbacks;
drop policy if exists "Admin deletes feedbacks" on public.feedbacks;
create policy "Anyone can send feedback" on public.feedbacks
  for insert to anon, authenticated with check (true);
create policy "Admin reads feedbacks" on public.feedbacks
  for select to authenticated using (public.is_admin());
create policy "Admin deletes feedbacks" on public.feedbacks
  for delete to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------
-- 6. Temps reel (idempotent)
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['profiles', 'likes', 'messages', 'user_blocks'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. Nettoyage pour le lancement : anciens profils supprimes / de test
-- ---------------------------------------------------------------------
delete from public.profiles
 where name in ('__DELETED__', 'Test Col', 'Test Onboarding')
    or email like '%@example.com';

-- Recharger le cache de l'API pour voir les nouvelles colonnes tout de suite
notify pgrst, 'reload schema';
