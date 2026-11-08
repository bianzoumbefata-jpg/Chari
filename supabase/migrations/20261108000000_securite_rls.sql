-- =====================================================================
-- Chari : verrouillage de la base (Row Level Security)
-- A executer UNE FOIS dans Supabase > SQL Editor (idempotent).
--
-- Avant ce script, la cle publique (anon) permettait a N'IMPORTE QUI de :
--   - lire tous les messages prives,
--   - modifier ou se faire passer pour n'importe quel profil,
--   - se mettre Premium sans payer,
--   - ecraser les photos des autres.
--
-- Apres ce script :
--   - seul un membre connecte (Google) voit les profils et photos ;
--   - chacun ne modifie QUE son propre profil, ses photos, ses likes,
--     ses blocages ;
--   - un message n'est lisible que par son expediteur, son destinataire
--     et l'administrateur ;
--   - is_premium ne peut etre change que par l'administrateur
--     (ou le serveur avec la cle service_role, ex. webhook de paiement).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. "Est-ce mon profil ?"
--    Un profil m'appartient si son id = mon id de connexion, ou (anciens
--    comptes) si son e-mail = l'e-mail de ma session.
-- ---------------------------------------------------------------------
create or replace function public.is_me(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and p_id is not null
     and (
       p_id = auth.uid()
       or exists (
         select 1
         from public.profiles pr
         where pr.id = p_id
           and pr.email is not null
           and coalesce(auth.jwt() ->> 'email', '') <> ''
           and lower(pr.email) = lower(auth.jwt() ->> 'email')
       )
     );
$$;

grant execute on function public.is_me(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Supprimer TOUTES les anciennes politiques des tables de l'app
--    (y compris celles creees a la main dans le tableau de bord).
-- ---------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select policyname, tablename
    from pg_policies
    where schemaname = 'public'
      and tablename in ('profiles', 'user_photos', 'likes', 'messages', 'feedbacks', 'user_blocks')
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end;
$$;

alter table public.profiles    enable row level security;
alter table public.user_photos enable row level security;
alter table public.likes       enable row level security;
alter table public.messages    enable row level security;
alter table public.feedbacks   enable row level security;
alter table public.user_blocks enable row level security;

-- ---------------------------------------------------------------------
-- 3. PROFILS
-- ---------------------------------------------------------------------
create policy "Membres connectes lisent les profils" on public.profiles
  for select to authenticated
  using (true);

create policy "Je cree mon propre profil" on public.profiles
  for insert to authenticated
  with check (
    id = auth.uid()
    and (email is null or lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')))
  );

create policy "Je modifie mon propre profil" on public.profiles
  for update to authenticated
  using (public.is_me(id) or public.is_admin())
  with check (
    public.is_admin()
    or (
      public.is_me(id)
      and (email is null or lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')))
    )
  );

create policy "Admin supprime les profils" on public.profiles
  for delete to authenticated
  using (public.is_admin());

-- Premium : jamais modifiable par le membre lui-meme.
create or replace function public.protect_premium()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.is_admin() or coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.is_premium := false;
  else
    new.is_premium := old.is_premium;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_premium on public.profiles;
create trigger trg_protect_premium
  before insert or update on public.profiles
  for each row execute function public.protect_premium();

-- Action admin : activer / retirer le Premium d'un membre.
create or replace function public.admin_set_premium(p_user_id uuid, p_premium boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Acces refuse' using errcode = '42501';
  end if;
  update public.profiles set is_premium = p_premium where id = p_user_id;
end;
$$;

revoke execute on function public.admin_set_premium(uuid, boolean) from public, anon;
grant execute on function public.admin_set_premium(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- 4. PHOTOS
-- ---------------------------------------------------------------------
create policy "Membres connectes voient les photos" on public.user_photos
  for select to authenticated
  using (true);

create policy "Je gere mes photos (ajout)" on public.user_photos
  for insert to authenticated
  with check (public.is_me(user_id));

create policy "Je gere mes photos (modif)" on public.user_photos
  for update to authenticated
  using (public.is_me(user_id) or public.is_admin())
  with check (public.is_me(user_id) or public.is_admin());

create policy "Je gere mes photos (suppression)" on public.user_photos
  for delete to authenticated
  using (public.is_me(user_id) or public.is_admin());

-- ---------------------------------------------------------------------
-- 5. LIKES / MATCHS
-- ---------------------------------------------------------------------
create policy "Je vois mes likes" on public.likes
  for select to authenticated
  using (public.is_me(sender_id) or public.is_me(receiver_id) or public.is_admin());

create policy "J'envoie mes likes" on public.likes
  for insert to authenticated
  with check (public.is_me(sender_id));

create policy "Je mets a jour mes likes" on public.likes
  for update to authenticated
  using (public.is_me(sender_id) or public.is_me(receiver_id))
  with check (public.is_me(sender_id) or public.is_me(receiver_id));

create policy "Je retire mes likes" on public.likes
  for delete to authenticated
  using (public.is_me(sender_id) or public.is_me(receiver_id) or public.is_admin());

-- Un "match" n'est valable que si l'autre personne a aussi like
-- (ou si c'est le destinataire qui accepte la demande).
create or replace function public.protect_match()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.is_match
     and not public.is_admin()
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and not public.is_me(new.receiver_id)
     and not exists (
       select 1 from public.likes l
       where l.sender_id = new.receiver_id
         and l.receiver_id = new.sender_id
     )
  then
    new.is_match := false;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_match on public.likes;
create trigger trg_protect_match
  before insert or update on public.likes
  for each row execute function public.protect_match();

-- ---------------------------------------------------------------------
-- 6. MESSAGES PRIVES
-- ---------------------------------------------------------------------
create policy "Je lis mes conversations" on public.messages
  for select to authenticated
  using (public.is_me(sender_id) or public.is_me(receiver_id) or public.is_admin());

create policy "J'envoie en mon nom" on public.messages
  for insert to authenticated
  with check (public.is_me(sender_id));

create policy "Je corrige mon message (10 min)" on public.messages
  for update to authenticated
  using (public.is_me(sender_id) and created_at > now() - interval '10 minutes')
  with check (public.is_me(sender_id));

create policy "Admin supprime les messages" on public.messages
  for delete to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- 7. BLOCAGES / SIGNALEMENTS
--    L'app enregistre aussi le "passage" dans les deux sens : on autorise
--    donc a ecrire une ligne "X m'a passe" (sans effet nuisible).
-- ---------------------------------------------------------------------
create policy "Je vois mes blocages" on public.user_blocks
  for select to authenticated
  using (public.is_me(user_id) or public.is_admin());

create policy "Je bloque / passe" on public.user_blocks
  for insert to authenticated
  with check (
    public.is_me(user_id)
    or (public.is_me(blocked_id) and reason = 'passed')
  );

create policy "Je modifie mes blocages" on public.user_blocks
  for update to authenticated
  using (public.is_me(user_id))
  with check (public.is_me(user_id));

create policy "Je retire mes blocages" on public.user_blocks
  for delete to authenticated
  using (public.is_me(user_id) or public.is_admin());

-- ---------------------------------------------------------------------
-- 8. AVIS (feedbacks)
-- ---------------------------------------------------------------------
create policy "Envoyer un avis" on public.feedbacks
  for insert to anon, authenticated
  with check (user_id is null or public.is_me(user_id));

create policy "Admin lit les avis" on public.feedbacks
  for select to authenticated
  using (public.is_admin());

create policy "Admin supprime les avis" on public.feedbacks
  for delete to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- 9. STOCKAGE DES PHOTOS (bucket "photo")
--    Lecture publique conservee (les URL sont utilisees directement),
--    mais seul un membre connecte peut envoyer, et seul l'auteur d'un
--    fichier peut l'ecraser ou le supprimer.
-- ---------------------------------------------------------------------
drop policy if exists "Allow public uploads to photo bucket" on storage.objects;
drop policy if exists "Allow public updates to photo bucket" on storage.objects;
drop policy if exists "Chari: membres envoient des photos" on storage.objects;
drop policy if exists "Chari: auteur modifie sa photo" on storage.objects;
drop policy if exists "Chari: auteur supprime sa photo" on storage.objects;

create policy "Chari: membres envoient des photos" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'photo');

create policy "Chari: auteur modifie sa photo" on storage.objects
  for update to authenticated
  using (bucket_id = 'photo' and owner_id = (select auth.uid())::text)
  with check (bucket_id = 'photo' and owner_id = (select auth.uid())::text);

create policy "Chari: auteur supprime sa photo" on storage.objects
  for delete to authenticated
  using (bucket_id = 'photo' and (owner_id = (select auth.uid())::text or public.is_admin()));

-- Index utiles aux nouvelles regles
create index if not exists likes_receiver_idx on public.likes (receiver_id);
create index if not exists user_blocks_user_idx on public.user_blocks (user_id);
create index if not exists user_photos_user_idx on public.user_photos (user_id);
create index if not exists profiles_email_lower_idx on public.profiles (lower(email));

notify pgrst, 'reload schema';
