-- Migration Chari : Politique de suppression, nettoyage des données et autorisations
-- À exécuter si souhaité dans Supabase SQL Editor pour remise à zéro complète

-- 1. Autoriser la suppression des profils par l'administrateur / client
CREATE POLICY IF NOT EXISTS "Allow delete profiles" ON public.profiles
  FOR DELETE USING (true);

-- 2. Nettoyage complet de toutes les données existantes (remise à zéro absolue)
TRUNCATE TABLE public.messages CASCADE;
TRUNCATE TABLE public.likes CASCADE;
TRUNCATE TABLE public.user_photos CASCADE;
TRUNCATE TABLE public.user_blocks CASCADE;
TRUNCATE TABLE public.feedbacks CASCADE;
TRUNCATE TABLE public.profiles CASCADE;

-- 3. (Optionnel pour l'administrateur) Remise à zéro des comptes d'authentification Supabase :
-- DELETE FROM auth.users;
