-- Active la synchronisation en temps réel (Supabase Realtime) sur toutes les tables
-- Exécutez ce script dans l'éditeur SQL de Supabase (SQL Editor) pour que la base de données
-- diffuse automatiquement chaque action (INSERT, UPDATE, DELETE) vers l'application et Vercel.

begin;

-- 1. Ajouter les tables de Chari à la publication supabase_realtime
alter publication supabase_realtime add table public.profiles;
alter publication supabase_realtime add table public.likes;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.feedbacks;
alter publication supabase_realtime add table public.user_blocks;

-- 2. Définir le niveau d'identité de réplication à FULL pour recevoir les états avant/après
alter table public.profiles replica identity full;
alter table public.likes replica identity full;
alter table public.messages replica identity full;
alter table public.feedbacks replica identity full;
alter table public.user_blocks replica identity full;

commit;
