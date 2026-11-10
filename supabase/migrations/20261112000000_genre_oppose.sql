-- =====================================================================
-- Chari : uniquement des profils de genre oppose (homme <-> femme)
-- Idempotent. Prerequis : 20261111 applique.
-- La regle est verifiee par la base, pas seulement par l'app.
-- =====================================================================

-- 1. Les membres renvoyes par list_members sont du genre oppose
create or replace function public.list_members(p_ids uuid[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid;
  v_gender text;
  v_out jsonb;
begin
  select id, gender into v_me, v_gender from public.get_my_profile();
  if v_me is null or v_gender is null then
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
      and p.gender is not null and p.gender <> v_gender
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

-- 2. Un "j'aime" ne peut viser qu'une personne de genre oppose
drop policy if exists "J'envoie mes likes" on public.likes;
create policy "J'envoie mes likes" on public.likes
  for insert to authenticated
  with check (
    public.is_me(sender_id)
    and exists (
      select 1 from public.profiles a, public.profiles b
       where a.id = sender_id and b.id = receiver_id
         and a.gender is not null and b.gender is not null
         and a.gender <> b.gender
    )
  );

-- 3. Les messages ne passent qu'entre personnes de genre oppose ayant un match
drop policy if exists "J'envoie en mon nom" on public.messages;
create policy "J'envoie en mon nom" on public.messages
  for insert to authenticated
  with check (
    public.is_me(sender_id)
    and public.is_matched(sender_id, receiver_id)
    and exists (
      select 1 from public.profiles a, public.profiles b
       where a.id = sender_id and b.id = receiver_id
         and a.gender is not null and b.gender is not null
         and a.gender <> b.gender
    )
  );

notify pgrst, 'reload schema';
