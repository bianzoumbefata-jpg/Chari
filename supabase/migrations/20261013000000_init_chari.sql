-- Schéma initial pour Chari - Rencontres au Tchad

-- 1. Profils utilisateurs
create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  phone text unique,
  email text unique,
  name text not null,
  gender text check (gender in ('f', 'm')),
  age int check (age >= 22),
  city text not null,
  target_city text default 'all',
  job text,
  bio text,
  language text default 'fr',
  religion text default 'mus',
  children int default 0,
  intention text default 'ser',
  hobbies text[] default '{}',
  selfie_url text,
  is_verified boolean default false,
  is_premium boolean default false,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

-- 2. Photos des utilisateurs (5 photos max)
create table if not exists public.user_photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  photo_url text not null,
  blurred_url text not null,
  is_selfie boolean default false,
  position int default 0,
  created_at timestamp with time zone default now()
);

-- 3. Matchs et Likes
create table if not exists public.likes (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid references public.profiles(id) on delete cascade,
  receiver_id uuid references public.profiles(id) on delete cascade,
  is_match boolean default false,
  created_at timestamp with time zone default now(),
  unique (sender_id, receiver_id)
);

-- 4. Messages (Texte, Photo, Note vocale)
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid references public.profiles(id) on delete cascade,
  receiver_id uuid references public.profiles(id) on delete cascade,
  content text,
  image_url text,
  voice_url text,
  duration text,
  created_at timestamp with time zone default now()
);

-- 5. Retours et Avis utilisateurs (Feedbacks)
create table if not exists public.feedbacks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  user_name text,
  rating int check (rating between 1 and 5),
  category text,
  message text not null,
  created_at timestamp with time zone default now()
);

-- 6. Signalements et blocages
create table if not exists public.user_blocks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  blocked_id uuid references public.profiles(id) on delete cascade,
  reason text,
  created_at timestamp with time zone default now()
);

-- Activer Row Level Security (RLS)
alter table public.profiles enable row level security;
alter table public.user_photos enable row level security;
alter table public.likes enable row level security;
alter table public.messages enable row level security;
alter table public.feedbacks enable row level security;
alter table public.user_blocks enable row level security;

-- Politiques RLS permissives pour la clé publique anon
create policy "Allow read profiles" on public.profiles for select using (true);
create policy "Allow insert profiles" on public.profiles for insert with check (true);
create policy "Allow update profiles" on public.profiles for update using (true);

create policy "Allow all user_photos" on public.user_photos for all using (true) with check (true);
create policy "Allow all likes" on public.likes for all using (true) with check (true);
create policy "Allow all messages" on public.messages for all using (true) with check (true);
create policy "Allow all feedbacks" on public.feedbacks for all using (true) with check (true);
create policy "Allow all user_blocks" on public.user_blocks for all using (true) with check (true);
