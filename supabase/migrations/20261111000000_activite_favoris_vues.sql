-- =====================================================================
-- Chari : Activite (vues de profil, favoris) + suppression de compte
-- Idempotent. Prerequis : 20261108 et 20261109 appliques.
-- =====================================================================

-- 1. Favoris (prives : seul l'auteur les voit)
create table if not exists public.favorites (
  user_id   uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, target_id)
);
alter table public.favorites enable row level security;
drop policy if exists "Mes favoris" on public.favorites;
create policy "Mes favoris" on public.favorites
  for all to authenticated
  using (public.is_me(user_id))
  with check (public.is_me(user_id) and user_id <> target_id);

-- 2. Vues de profil (une ligne par visiteur et par profil, date mise a jour)
create table if not exists public.profile_views (
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  viewed_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (viewer_id, viewed_id)
);
alter table public.profile_views enable row level security;
-- Lecture directe interdite : on passe par my_viewers() (respecte l'incognito)
drop policy if exists "Admin voit les vues" on public.profile_views;
create policy "Admin voit les vues" on public.profile_views
  for select to authenticated using (public.is_admin());

create index if not exists profile_views_viewed_idx on public.profile_views (viewed_id, viewed_at desc);

-- Enregistrer une visite (ignoree si le visiteur est en mode incognito)
create or replace function public.record_view(p_target uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid;
  v_incog boolean;
begin
  select id, coalesce(is_incognito, false) into v_me, v_incog from public.get_my_profile();
  if v_me is null or p_target is null or p_target = v_me or v_incog then
    return;
  end if;
  insert into public.profile_views (viewer_id, viewed_id, viewed_at)
  values (v_me, p_target, now())
  on conflict (viewer_id, viewed_id) do update set viewed_at = excluded.viewed_at;
end;
$$;
revoke execute on function public.record_view(uuid) from public, anon;
grant execute on function public.record_view(uuid) to authenticated;

-- Qui a vu mon profil (30 derniers jours, sans les personnes bloquees)
create or replace function public.my_viewers()
returns table (viewer_id uuid, viewed_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select v.viewer_id, v.viewed_at
    from public.profile_views v
    join public.get_my_profile() me on me.id = v.viewed_id
   where v.viewed_at > now() - interval '30 days'
     and not exists (select 1 from public.user_blocks b
                      where b.reason <> 'passed'
                        and ((b.user_id = me.id and b.blocked_id = v.viewer_id)
                          or (b.user_id = v.viewer_id and b.blocked_id = me.id)))
   order by v.viewed_at desc
   limit 100;
$$;
revoke execute on function public.my_viewers() from public, anon;
grant execute on function public.my_viewers() to authenticated;

-- 3. Le membre supprime lui-meme son compte (profil, photos, likes, messages, connexion)
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid;
begin
  select id into v_me from public.get_my_profile();
  if v_me is null then
    raise exception 'Aucun profil' using errcode = '42501';
  end if;
  delete from public.messages where sender_id = v_me or receiver_id = v_me;
  delete from public.likes where sender_id = v_me or receiver_id = v_me;
  delete from public.user_blocks where user_id = v_me or blocked_id = v_me;
  delete from public.user_photos where user_id = v_me;
  delete from public.profiles where id = v_me;
  delete from auth.users where id = auth.uid();
end;
$$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

notify pgrst, 'reload schema';
