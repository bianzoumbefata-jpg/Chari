-- =====================================================================
-- Chari : paiement Premium par carte (Stripe)
-- Le Premium dure 30 jours a partir du paiement (cumulable).
-- Seul le serveur (webhook Stripe, cle service_role) ou l'admin l'active.
-- =====================================================================

alter table public.profiles
  add column if not exists premium_until timestamptz;

grant select (premium_until) on public.profiles to authenticated;

-- Historique des paiements (un enregistrement par session Stripe payee)
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  provider text not null default 'stripe',
  provider_session_id text not null unique,
  amount integer not null,
  currency text not null,
  status text not null default 'paid',
  premium_until timestamptz,
  created_at timestamptz not null default now()
);
alter table public.payments enable row level security;

drop policy if exists "Je vois mes paiements" on public.payments;
create policy "Je vois mes paiements" on public.payments
  for select to authenticated
  using (public.is_me(user_id) or public.is_admin());
-- Aucune politique d'ecriture : seul le serveur (service_role) ecrit ici.

-- Premium expire automatiquement : on considere is_premium vrai seulement
-- si la date de fin n'est pas depassee (ou absente pour un Premium offert).
create or replace function public.premium_active(p public.profiles)
returns boolean
language sql
stable
as $$
  select coalesce(p.is_premium, false)
     and (p.premium_until is null or p.premium_until > now());
$$;

-- L'admin qui offre le Premium : 30 jours, ou retrait.
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
  update public.profiles
     set is_premium = p_premium,
         premium_until = case when p_premium
                              then greatest(coalesce(premium_until, now()), now()) + interval '30 days'
                              else null end
   where id = p_user_id;
end;
$$;

-- Le membre ne peut toujours pas modifier premium_until lui-meme.
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
    new.premium_until := null;
  else
    new.is_premium := old.is_premium;
    new.premium_until := old.premium_until;
  end if;
  return new;
end;
$$;

notify pgrst, 'reload schema';
