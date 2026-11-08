-- =====================================================================
-- Chari v2 : international, date de naissance (25 ans min), WhatsApp,
-- green/red flags, devoilement mutuel des photos, certification admin.
-- Prerequis : 20261108000000_securite_rls.sql deja applique.
-- Idempotent : peut etre relance.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Suppression des comptes de test
-- ---------------------------------------------------------------------
delete from auth.users
 where id in (
   select id from public.profiles
    where name in ('__DELETED__', 'Test Col', 'Test Onboarding')
       or email like '%@example.com' or email like '%@test.com'
 );
delete from public.profiles
 where name in ('__DELETED__', 'Test Col', 'Test Onboarding')
    or email like '%@example.com' or email like '%@test.com';

-- ---------------------------------------------------------------------
-- 1. Nouvelles colonnes de profil
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists birth_date date,
  add column if not exists country text default 'TD',
  add column if not exists target_country text default 'all',
  add column if not exists whatsapp text,
  add column if not exists green_flags text[] not null default '{}',
  add column if not exists red_flags text[] not null default '{}',
  add column if not exists avatar_blur_url text;

alter table public.profiles drop constraint if exists profiles_age_check;
alter table public.profiles drop constraint if exists profiles_whatsapp_check;
alter table public.profiles
  add constraint profiles_whatsapp_check
  check (whatsapp is null or whatsapp ~ '^\+[1-9][0-9]{6,14}$');
alter table public.profiles drop constraint if exists profiles_flags_check;
alter table public.profiles
  add constraint profiles_flags_check
  check (cardinality(green_flags) <= 5 and cardinality(red_flags) <= 5);

alter table public.user_photos
  add column if not exists poster_url text,
  add column if not exists is_video boolean not null default false;

-- Age calcule depuis la date de naissance, 25 ans minimum.
create or replace function public.enforce_birth_date()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_age int;
begin
  if public.is_admin() or coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    if new.birth_date is not null then
      new.age := extract(year from age(current_date, new.birth_date))::int;
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' and new.birth_date is null then
    raise exception 'Date de naissance obligatoire' using errcode = '23514';
  end if;

  if new.birth_date is not null then
    v_age := extract(year from age(current_date, new.birth_date))::int;
    if v_age < 25 then
      raise exception 'Chari est reserve aux 25 ans et plus' using errcode = '23514';
    end if;
    if v_age > 99 then
      raise exception 'Date de naissance invalide' using errcode = '23514';
    end if;
    new.age := v_age;
  elsif tg_op = 'UPDATE' then
    new.age := old.age;  -- pas de modification directe de l'age sans date
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_birth_date on public.profiles;
create trigger trg_enforce_birth_date
  before insert or update on public.profiles
  for each row execute function public.enforce_birth_date();

-- ---------------------------------------------------------------------
-- 2. Devoilement mutuel
-- ---------------------------------------------------------------------
create table if not exists public.reveals (
  user_id   uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, target_id)
);
alter table public.reveals enable row level security;

create or replace function public.is_matched(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.likes l
    where l.is_match
      and ((l.sender_id = a and l.receiver_id = b) or (l.sender_id = b and l.receiver_id = a))
  );
$$;

create or replace function public.is_revealed(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.reveals r where r.user_id = a and r.target_id = b)
     and exists (select 1 from public.reveals r where r.user_id = b and r.target_id = a);
$$;

drop policy if exists "Je vois les devoilements me concernant" on public.reveals;
drop policy if exists "Je me devoile a un match" on public.reveals;
drop policy if exists "Je retire mon devoilement" on public.reveals;
create policy "Je vois les devoilements me concernant" on public.reveals
  for select to authenticated
  using (public.is_me(user_id) or public.is_me(target_id) or public.is_admin());
create policy "Je me devoile a un match" on public.reveals
  for insert to authenticated
  with check (public.is_me(user_id) and public.is_matched(user_id, target_id));
create policy "Je retire mon devoilement" on public.reveals
  for delete to authenticated
  using (public.is_me(user_id));

-- ---------------------------------------------------------------------
-- 3. Confidentialite des colonnes : e-mail, telephone, WhatsApp, date de
--    naissance et photos nettes ne sont plus lisibles directement.
--    L'app passe par les fonctions ci-dessous.
-- ---------------------------------------------------------------------
revoke select on public.profiles from anon, authenticated;
grant select (
  id, name, gender, age, city, country, target_city, target_country, job, bio,
  language, religion, children, intention, hobbies, is_verified, is_premium,
  is_incognito, selfie_status, green_flags, red_flags, avatar_blur_url,
  created_at, updated_at
) on public.profiles to authenticated;

revoke select on public.user_photos from anon, authenticated;
grant select (id, user_id, blurred_url, is_selfie, is_video, position, created_at)
  on public.user_photos to authenticated;

-- Le temps reel sur profiles diffuserait toutes les colonnes : on le coupe.
do $$
begin
  if exists (select 1 from pg_publication_tables
             where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'profiles') then
    alter publication supabase_realtime drop table public.profiles;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'reveals') then
    alter publication supabase_realtime add table public.reveals;
  end if;
end;
$$;

-- Mon propre profil complet
create or replace function public.get_my_profile()
returns setof public.profiles
language sql
stable
security definer
set search_path = ''
as $$
  select p.* from public.profiles p
   where public.is_me(p.id)
   order by (p.id = auth.uid()) desc
   limit 1;
$$;
revoke execute on function public.get_my_profile() from public, anon;
grant execute on function public.get_my_profile() to authenticated;

-- Profils des autres membres, avec photos nettes uniquement si devoilement mutuel.
-- p_ids null  = decouverte (membres certifies, visibles, hors bloques)
-- p_ids donne = ces membres s'ils sont certifies ou lies a moi (like / match)
create or replace function public.list_members(p_ids uuid[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid;
  v_out jsonb;
begin
  select id into v_me from public.get_my_profile();
  if v_me is null then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(m order by m.created_at desc), '[]'::jsonb) into v_out
  from (
    select
      p.id, p.name, p.gender, p.age, p.city, p.country, p.target_city, p.target_country,
      p.job, p.bio, p.language, p.religion, p.children, p.intention, p.hobbies,
      p.is_verified, p.is_premium, p.selfie_status, p.green_flags, p.red_flags, p.created_at,
      public.is_matched(v_me, p.id) as is_match,
      public.is_revealed(v_me, p.id) as revealed,
      exists (select 1 from public.reveals r where r.user_id = v_me and r.target_id = p.id) as i_revealed,
      exists (select 1 from public.reveals r where r.user_id = p.id and r.target_id = v_me) as they_revealed,
      case when public.is_revealed(v_me, p.id) then p.whatsapp end as whatsapp,
      case when public.is_revealed(v_me, p.id)
           then coalesce(p.avatar_url, p.selfie_url)
           else p.avatar_blur_url end as avatar,
      coalesce((
        select jsonb_agg(jsonb_build_object(
                 'url', case when public.is_revealed(v_me, p.id) then up.photo_url else up.blurred_url end,
                 'poster', case when public.is_revealed(v_me, p.id) then up.poster_url else up.blurred_url end,
                 'video', (up.is_video and public.is_revealed(v_me, p.id)),
                 'selfie', up.is_selfie)
               order by up.position)
          from public.user_photos up where up.user_id = p.id
      ), '[]'::jsonb) as photos
    from public.profiles p
    where p.id <> v_me
      and p.name is not null and p.name <> '__DELETED__'
      and not exists (select 1 from public.user_blocks b
                       where b.reason <> 'passed'
                         and ((b.user_id = v_me and b.blocked_id = p.id)
                           or (b.user_id = p.id and b.blocked_id = v_me)))
      and (
        (p_ids is null and p.selfie_status = 'approved' and not coalesce(p.is_incognito, false))
        or
        (p_ids is not null and p.id = any(p_ids) and (
           p.selfie_status = 'approved'
           or exists (select 1 from public.likes l
                       where (l.sender_id = v_me and l.receiver_id = p.id)
                          or (l.sender_id = p.id and l.receiver_id = v_me))))
      )
  ) m;
  return v_out;
end;
$$;
revoke execute on function public.list_members(uuid[]) from public, anon;
grant execute on function public.list_members(uuid[]) to authenticated;

-- Mes photos completes (pour mon propre profil)
create or replace function public.get_my_photos()
returns setof public.user_photos
language sql
stable
security definer
set search_path = ''
as $$
  select up.* from public.user_photos up
   where public.is_me(up.user_id)
   order by up.position;
$$;
revoke execute on function public.get_my_photos() from public, anon;
grant execute on function public.get_my_photos() to authenticated;

-- ---------------------------------------------------------------------
-- 4. Administration
-- ---------------------------------------------------------------------
create or replace function public.admin_list_profiles()
returns setof public.profiles
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Acces refuse' using errcode = '42501';
  end if;
  return query select * from public.profiles order by created_at desc;
end;
$$;
revoke execute on function public.admin_list_profiles() from public, anon;
grant execute on function public.admin_list_profiles() to authenticated;

create or replace function public.admin_list_photos(p_user_id uuid)
returns setof public.user_photos
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Acces refuse' using errcode = '42501';
  end if;
  return query select * from public.user_photos where user_id = p_user_id order by position;
end;
$$;
revoke execute on function public.admin_list_photos(uuid) from public, anon;
grant execute on function public.admin_list_photos(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Messages : uniquement entre personnes en match
-- ---------------------------------------------------------------------
drop policy if exists "J'envoie en mon nom" on public.messages;
create policy "J'envoie en mon nom" on public.messages
  for insert to authenticated
  with check (public.is_me(sender_id) and public.is_matched(sender_id, receiver_id));

-- ---------------------------------------------------------------------
-- 6. Stockage : plus de listing public du bucket (les URL restent valides)
-- ---------------------------------------------------------------------
drop policy if exists "Allow public view from photo bucket" on storage.objects;

notify pgrst, 'reload schema';
