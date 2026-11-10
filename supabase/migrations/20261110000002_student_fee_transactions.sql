alter table public.student_payments enable row level security;

create policy "Students read their own payment transactions" on public.student_payments
  for select to authenticated using (
    exists (
      select 1 from public.students
      where students.admission_number = student_payments.admission_number
        and students.auth_user_id = (select auth.uid())
    )
  );

grant select on public.student_payments to authenticated;

-- Copy each payment from the encrypted-statement source into a durable ledger.
insert into public.student_payments (id, admission_number, amount, reference, paid_on)
select
  pg_catalog.md5(students.admission_number || ':' || payment.ordinality::text)::uuid,
  students.admission_number,
  (payment.entry->>'amt')::numeric,
  coalesce(payment.entry->>'ref', ''),
  case
    when payment.entry->>'date' ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
      then pg_catalog.to_date(payment.entry->>'date', 'DD/MM/YYYY')
    else current_date
  end
from public.students
cross join lateral jsonb_array_elements(coalesce(students.payments, '[]'::jsonb))
  with ordinality as payment(entry, ordinality)
where payment.entry ? 'amt'
on conflict (id) do nothing;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'student_payments'
     ) then
    alter publication supabase_realtime add table public.student_payments;
  end if;
end;
$$;
