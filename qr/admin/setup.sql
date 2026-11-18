-- MATAR QR HUB admin storage and owner-only editing.
-- Run this once in the Supabase SQL Editor for project zvxotwnwdkywttdjojpx.
-- BEFORE RUNNING: Replace the text PUT_OWNER_EMAIL_HERE at the bottom
-- with the email address used by the owner to sign into Supabase.
-- Do not publish service_role keys or Supabase passwords.
begin;
create table if not exists public.matar_qr_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  added_at timestamptz not null default now()
);
alter table public.matar_qr_admins enable row level security;
revoke all on table public.matar_qr_admins from anon, authenticated;

create or replace function public.matar_qr_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
      from public.matar_qr_admins a
     where a.user_id = (select auth.uid())
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
-- Only an existing authenticated owner gets access.
do $owner$
declare
  email_input text := 'PUT_OWNER_EMAIL_HERE';
  owner_uuid uuid;
begin
  if email_input = 'PUT_OWNER_EMAIL_HERE' then
    raise exception 'Replace PUT_OWNER_EMAIL_HERE with your actual owner login email and run again.';
  end if;
  select id into owner_uuid
    from auth.users where lower(email)=lower(email_input) limit 1;
  if owner_uuid is null then
    raise exception 'No Supabase Auth user found with email %. Check Auth > Users.',email_input;
  end if;
  insert into public.matar_qr_admins(user_id) values (owner_uuid)
    on conflict do nothing;
end
$owner$;
commit;