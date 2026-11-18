-- MATAR QR HUB admin storage and owner-only editing.
-- Run once in the Supabase SQL Editor of project zvxotwnwdkywttdjojpx.
-- Uses existing MATAR CLUB staff table. Only active owners can edit the QR hub.
-- No new user login, owner email, password, or API secret is needed here.
begin;

create or replace function public.matar_qr_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
      from public.matar_staff s
     where s.auth_user_id = (select auth.uid())
       and s.role = 'owner'
       and s.active is true
  );
$fn$;
revoke all on function public.matar_qr_is_admin() from public;
grant execute on function public.matar_qr_is_admin() to authenticated;

create table if not exists public.matar_qr_content (
  id text primary key check (id = 'main'),
  content jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  constraint qr_content_object check (jsonb_typeof(content)='object')
);
alter table public.matar_qr_content enable row level security;
grant select on public.matar_qr_content to anon, authenticated;
grant insert,update on public.matar_qr_content to authenticated;
revoke delete on public.matar_qr_content from anon,authenticated;

drop policy if exists qr_public_read on public.matar_qr_content;
create policy qr_public_read on public.matar_qr_content
  for select to anon,authenticated using (id='main');

drop policy if exists qr_owner_insert on public.matar_qr_content;
create policy qr_owner_insert on public.matar_qr_content
  for insert to authenticated
  with check (id='main' and public.matar_qr_is_admin()
              and updated_by=(select auth.uid()));

drop policy if exists qr_owner_update on public.matar_qr_content;
create policy qr_owner_update on public.matar_qr_content
  for update to authenticated
  using (id='main' and public.matar_qr_is_admin())
  with check (id='main' and public.matar_qr_is_admin()
              and updated_by=(select auth.uid()));

-- Public images only (no sensitive files). Owners can upload.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('matar-qr-media','matar-qr-media',true,4194304,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public=excluded.public,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists qr_media_public_read on storage.objects;
create policy qr_media_public_read on storage.objects
for select to public using (bucket_id='matar-qr-media');

drop policy if exists qr_media_owner_upload on storage.objects;
create policy qr_media_owner_upload on storage.objects
for insert to authenticated
with check (bucket_id='matar-qr-media' and public.matar_qr_is_admin());

-- No overwrite/delete policy by design: new image uploads use unique paths.
-- Before opening the admin page, verify the owner already exists in public.matar_staff.
commit;
