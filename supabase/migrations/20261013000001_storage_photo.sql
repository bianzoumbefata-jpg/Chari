-- Configuration des droits de stockage pour le bucket 'photo'

-- 1. S'assurer que le bucket est public (accessible en lecture directe)
update storage.buckets set public = true where id = 'photo';

-- 2. Autoriser l'envoi de photos (insert) dans le bucket 'photo'
create policy "Allow public uploads to photo bucket"
on storage.objects for insert
to public
with check (bucket_id = 'photo');

-- 3. Autoriser la lecture publique des photos (select)
create policy "Allow public view from photo bucket"
on storage.objects for select
to public
using (bucket_id = 'photo');

-- 4. Autoriser la mise à jour des photos (update)
create policy "Allow public updates to photo bucket"
on storage.objects for update
to public
using (bucket_id = 'photo')
with check (bucket_id = 'photo');
