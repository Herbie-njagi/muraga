-- Demo rows are unpublished so they never appear on the public site by accident.
insert into public.courses (id, department, campus, name, level, duration, is_published)
values
  ('00000000-0000-4000-8000-000000000101', 'Electrical & Electronics Engineering', 'Main Campus', 'SAMPLE - Electrical Installation', 'Level 4', '1 Module', false),
  ('00000000-0000-4000-8000-000000000102', 'Information & Communication Technology', 'Kaare Campus', 'SAMPLE - ICT Support', 'Level 5', '2 Modules', false)
on conflict (id) do nothing;

insert into public.announcements (id, title, body, display_date, is_published)
values ('00000000-0000-4000-8000-000000000201', 'SAMPLE - Intake notice', 'Demo announcement for testing the admin panel.', '10 November 2026', false)
on conflict (id) do nothing;

insert into public.staff_profiles (id, name, role, department, campus, is_published)
values ('00000000-0000-4000-8000-000000000301', 'Sample Staff Member', 'Trainer', 'Information & Communication Technology', 'Main Campus', false)
on conflict (id) do nothing;

insert into public.testimonials (id, name, role, body, is_published)
values ('00000000-0000-4000-8000-000000000401', 'Sample Graduate', 'Demo testimonial', 'Sample content for checking the testimonials section.', false)
on conflict (id) do nothing;

insert into public.applications (
  id, reference, full_name, phone, email, education, campus, department,
  course, message, display_date, status
)
values (
  '00000000-0000-4000-8000-000000000501', 'SAMPLE-APP-2026-001', 'Demo Applicant',
  '0700000000', 'demo@example.invalid', 'Sample KCSE record', 'Main Campus',
  'Electrical & Electronics Engineering', 'SAMPLE - Electrical Installation',
  'Demo application; safe to delete.', '10 November 2026', 'New'
)
on conflict (reference) do nothing;

-- Create this Auth user first in Supabase Authentication > Users.
-- Replace the email below with that exact user's email before running this block.
do $$
declare
  admin_email text := 'info@muragatechnical.ac.ke';
  admin_user_id uuid;
begin
  select id into admin_user_id
  from auth.users
  where lower(email) = lower(admin_email)
  limit 1;

  if admin_user_id is null then
    raise notice 'No Auth user matched %. Demo data was inserted; admin role was not changed.', admin_email;
  else
    insert into public.staff_roles (user_id, role)
    values (admin_user_id, 'admin')
    on conflict (user_id) do update set role = excluded.role;
    raise notice 'Admin role assigned to %.', admin_email;
  end if;
end;
$$;
