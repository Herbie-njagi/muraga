alter table public.students
  add column if not exists portal_enabled boolean not null default false;

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
    and portal_enabled
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

drop policy if exists "Students read their own roster record" on public.students;
create policy "Students read their own roster record" on public.students
  for select to authenticated using (portal_enabled and auth_user_id = (select auth.uid()));

drop policy if exists "Students read their own key" on public.student_keys;
create policy "Students read their own key" on public.student_keys
  for select to authenticated using (
    exists (
      select 1 from public.students
      where students.admission_number = student_keys.admission_number
        and students.auth_user_id = (select auth.uid())
        and students.portal_enabled
    )
  );

drop policy if exists "Students read their own key secrets" on public.student_key_secrets;
create policy "Students read their own key secrets" on public.student_key_secrets
  for select to authenticated using (
    exists (
      select 1 from public.students
      where students.admission_number = student_key_secrets.admission_number
        and students.auth_user_id = (select auth.uid())
        and students.portal_enabled
    )
  );

drop policy if exists "Students read their own statements" on public.student_statements;
create policy "Students read their own statements" on public.student_statements
  for select to authenticated using (
    exists (
      select 1 from public.students
      where students.admission_number = student_statements.admission_number
        and students.auth_user_id = (select auth.uid())
        and students.portal_enabled
    )
  );

drop policy if exists "Students read their own results" on public.results;
create policy "Students read their own results" on public.results
  for select to authenticated using (
    exists (
      select 1 from public.students
      where students.admission_number = results.admission_number
        and students.auth_user_id = (select auth.uid())
        and students.portal_enabled
    )
  );

drop policy if exists "Students read their own payment transactions" on public.student_payments;
create policy "Students read their own payment transactions" on public.student_payments
  for select to authenticated using (
    exists (
      select 1 from public.students
      where students.admission_number = student_payments.admission_number
        and students.auth_user_id = (select auth.uid())
        and students.portal_enabled
    )
  );
