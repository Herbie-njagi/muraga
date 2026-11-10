alter table public.students
  add column if not exists auth_user_id uuid unique references auth.users (id) on delete set null,
  add column if not exists email text not null default '',
  add column if not exists payments jsonb not null default '[]'::jsonb;

create or replace function public.claim_student_account(p_admission_number text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  current_email text;
  email_confirmed_at timestamptz;
begin
  if current_user_id is null then
    raise exception 'Sign in before linking a student account';
  end if;

  select users.email, users.email_confirmed_at
  into current_email, email_confirmed_at
  from auth.users as users
  where users.id = current_user_id;

  if current_email is null or email_confirmed_at is null then
    raise exception 'Confirm your email before linking a student account';
  end if;

  update public.students
  set auth_user_id = current_user_id, updated_at = pg_catalog.now()
  where admission_number = p_admission_number
    and pg_catalog.lower(email) = pg_catalog.lower(current_email)
    and (auth_user_id is null or auth_user_id = current_user_id);

  if not found then
    raise exception 'The admission number and email could not be verified';
  end if;

  return true;
end;
$$;

revoke all on function public.claim_student_account(text) from public, anon;
grant execute on function public.claim_student_account(text) to authenticated;

create table if not exists public.student_key_secrets (
  admission_number text primary key references public.students (admission_number) on delete cascade,
  salt text not null,
  iv text not null,
  wrapped_private_key text not null,
  updated_at timestamptz not null default now()
);

alter table public.student_key_secrets enable row level security;

-- Preserve existing encrypted-key login material before removing it from the trainer-readable table.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'student_keys' and column_name = 'wrapped_private_key'
  ) then
    execute $migrate$
      insert into public.student_key_secrets (admission_number, salt, iv, wrapped_private_key, updated_at)
      select admission_number, salt, iv, wrapped_private_key, updated_at
      from public.student_keys
      on conflict (admission_number) do nothing
    $migrate$;
    alter table public.student_keys drop column if exists salt;
    alter table public.student_keys drop column if exists iv;
    alter table public.student_keys drop column if exists wrapped_private_key;
  end if;
end;
$$;

create table if not exists public.trainer_result_log (
  id uuid primary key references public.results (id) on delete cascade,
  admission_number text not null references public.students (admission_number) on delete cascade,
  teacher_id uuid not null references auth.users (id) on delete cascade,
  student_name text not null default '',
  unit text not null,
  assessment text not null default '',
  marks text not null default '',
  grade text not null default '',
  competency text not null default '',
  display_date text not null default '',
  created_at timestamptz not null default now()
);

alter table public.trainer_result_log enable row level security;

create policy "Students read their own roster record" on public.students
  for select to authenticated using (auth_user_id = (select auth.uid()));

create policy "Students read their own key" on public.student_keys
  for select to authenticated using (
    exists (
      select 1 from public.students
      where students.admission_number = student_keys.admission_number
        and students.auth_user_id = (select auth.uid())
    )
  );

create policy "Students read their own key secrets" on public.student_key_secrets
  for select to authenticated using (
    exists (
      select 1 from public.students
      where students.admission_number = student_key_secrets.admission_number
        and students.auth_user_id = (select auth.uid())
    )
  );
create policy "Admissions staff manage student key secrets" on public.student_key_secrets
  for all to authenticated using (public.has_staff_role(array['admin', 'admissions']))
  with check (public.has_staff_role(array['admin', 'admissions']));

create policy "Students read their own statements" on public.student_statements
  for select to authenticated using (
    exists (
      select 1 from public.students
      where students.admission_number = student_statements.admission_number
        and students.auth_user_id = (select auth.uid())
    )
  );

create policy "Students read their own results" on public.results
  for select to authenticated using (
    exists (
      select 1 from public.students
      where students.admission_number = results.admission_number
        and students.auth_user_id = (select auth.uid())
    )
  );

create policy "Trainers read their own result summaries and admins read all" on public.trainer_result_log
  for select to authenticated
  using (public.has_staff_role(array['admin']) or (teacher_id = (select auth.uid()) and public.has_staff_role(array['trainer'])));
create policy "Trainers add their own result summaries" on public.trainer_result_log
  for insert to authenticated
  with check (teacher_id = (select auth.uid()) and public.has_staff_role(array['admin', 'trainer']));
create policy "Trainers delete their own result summaries and admins delete all" on public.trainer_result_log
  for delete to authenticated
  using (public.has_staff_role(array['admin']) or (teacher_id = (select auth.uid()) and public.has_staff_role(array['trainer'])));

grant select, insert, update, delete on public.student_key_secrets, public.trainer_result_log to authenticated;

insert into storage.buckets (id, name, public)
values ('site-assets', 'site-assets', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "Public can read site assets" on storage.objects;
create policy "Public can read site assets" on storage.objects
  for select to anon, authenticated using (bucket_id = 'site-assets');
drop policy if exists "Admins upload site assets" on storage.objects;
create policy "Admins upload site assets" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'site-assets' and public.has_staff_role(array['admin']));
drop policy if exists "Admins update site assets" on storage.objects;
create policy "Admins update site assets" on storage.objects
  for update to authenticated using (bucket_id = 'site-assets' and public.has_staff_role(array['admin']))
  with check (bucket_id = 'site-assets' and public.has_staff_role(array['admin']));
drop policy if exists "Admins delete site assets" on storage.objects;
create policy "Admins delete site assets" on storage.objects
  for delete to authenticated using (bucket_id = 'site-assets' and public.has_staff_role(array['admin']));

do $$
declare
  table_name text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach table_name in array array['student_key_secrets', 'trainer_result_log'] loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = table_name
      ) then
        execute format('alter publication supabase_realtime add table public.%I', table_name);
      end if;
    end loop;
  end if;
end;
$$;
