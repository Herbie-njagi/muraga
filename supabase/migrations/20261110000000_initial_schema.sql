create table public.staff_roles (
	user_id uuid primary key references auth.users (id) on delete cascade,
	role text not null check (role in ('admin', 'admissions', 'trainer')),
	created_at timestamptz not null default now()
);

create or replace function public.has_staff_role(required_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select exists (
		select 1
		from public.staff_roles
		where user_id = (select auth.uid())
			and role = any (required_roles)
	);
$$;

create table public.courses (
	id uuid primary key default gen_random_uuid(),
	department text not null,
	campus text not null check (campus in ('Main Campus', 'Kaare Campus', 'Both Campuses')),
	name text not null,
	level text not null check (level in ('Level 4', 'Level 5', 'Level 6')),
	duration text not null,
	is_published boolean not null default true,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create table public.announcements (
	id uuid primary key default gen_random_uuid(),
	title text not null,
	body text not null default '',
	display_date text not null default '',
	is_published boolean not null default true,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create table public.staff_profiles (
	id uuid primary key default gen_random_uuid(),
	name text not null,
	role text not null,
	department text not null default '',
	campus text not null default '',
	asset_id text,
	is_published boolean not null default true,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create table public.gallery_items (
	id uuid primary key default gen_random_uuid(),
	asset_id text not null,
	caption text not null default '',
	is_published boolean not null default true,
	created_at timestamptz not null default now()
);

create table public.testimonials (
	id uuid primary key default gen_random_uuid(),
	name text not null default '',
	role text not null default '',
	body text not null,
	is_published boolean not null default true,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create table public.site_settings (
	key text primary key,
	value jsonb not null default '{}'::jsonb,
	updated_at timestamptz not null default now()
);

create table public.applications (
	id uuid primary key default gen_random_uuid(),
	reference text not null unique,
	full_name text not null,
	phone text not null,
	email text not null default '',
	education text not null default '',
	campus text not null default '',
	department text not null default '',
	course text not null default '',
	message text not null default '',
	display_date text not null default '',
	status text not null default 'New' check (status in ('New', 'Enrolled', 'Rejected')),
	admission_number text,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create table public.students (
	admission_number text primary key,
	auth_user_id uuid unique references auth.users (id) on delete set null,
	full_name text not null,
	email text not null default '',
	portal_enabled boolean not null default false,
	phone text not null default '',
	course text not null default '',
	campus text not null default '',
	total_fees numeric(12, 2) not null default 0 check (total_fees >= 0),
	payments jsonb not null default '[]'::jsonb,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create table public.student_payments (
	id uuid primary key default gen_random_uuid(),
	admission_number text not null references public.students (admission_number) on delete cascade,
	amount numeric(12, 2) not null check (amount > 0),
	reference text not null default '',
	paid_on date not null default current_date,
	recorded_by uuid references auth.users (id) on delete set null,
	created_at timestamptz not null default now()
);

create table public.student_keys (
	admission_number text primary key references public.students (admission_number) on delete cascade,
	public_key jsonb not null,
	updated_at timestamptz not null default now()
);

create table public.student_key_secrets (
	admission_number text primary key references public.students (admission_number) on delete cascade,
	salt text not null,
	iv text not null,
	wrapped_private_key text not null,
	updated_at timestamptz not null default now()
);

create table public.student_statements (
	admission_number text primary key references public.students (admission_number) on delete cascade,
	encrypted_key text not null,
	iv text not null,
	ciphertext text not null,
	updated_at timestamptz not null default now()
);

create table public.results (
	id uuid primary key default gen_random_uuid(),
	admission_number text not null references public.students (admission_number) on delete cascade,
	teacher_id uuid not null references auth.users (id) on delete restrict,
	encrypted_key text not null,
	iv text not null,
	ciphertext text not null,
	created_at timestamptz not null default now()
);

create table public.trainer_result_log (
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

create index applications_status_created_at_idx on public.applications (status, created_at desc);
create index student_payments_admission_number_idx on public.student_payments (admission_number, paid_on desc);
create index results_admission_number_created_at_idx on public.results (admission_number, created_at desc);
create index results_teacher_id_created_at_idx on public.results (teacher_id, created_at desc);

do $$
declare
	table_name text;
begin
	if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
		foreach table_name in array array[
			'announcements', 'courses', 'staff_profiles', 'gallery_items', 'testimonials',
			'site_settings', 'applications', 'students', 'student_keys', 'student_key_secrets',
			'student_statements', 'results', 'trainer_result_log', 'staff_roles'
		] loop
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

alter table public.staff_roles enable row level security;
alter table public.courses enable row level security;
alter table public.announcements enable row level security;
alter table public.staff_profiles enable row level security;
alter table public.gallery_items enable row level security;
alter table public.testimonials enable row level security;
alter table public.site_settings enable row level security;
alter table public.applications enable row level security;
alter table public.students enable row level security;
alter table public.student_payments enable row level security;
alter table public.student_keys enable row level security;
alter table public.student_key_secrets enable row level security;
alter table public.student_statements enable row level security;
alter table public.results enable row level security;
alter table public.trainer_result_log enable row level security;

create policy "Published courses are public" on public.courses
	for select to anon, authenticated using (is_published);
create policy "Admins manage courses" on public.courses
	for all to authenticated using (public.has_staff_role(array['admin']))
	with check (public.has_staff_role(array['admin']));

create policy "Published announcements are public" on public.announcements
	for select to anon, authenticated using (is_published);
create policy "Admins manage announcements" on public.announcements
	for all to authenticated using (public.has_staff_role(array['admin']))
	with check (public.has_staff_role(array['admin']));

create policy "Published staff profiles are public" on public.staff_profiles
	for select to anon, authenticated using (is_published);
create policy "Admins manage staff profiles" on public.staff_profiles
	for all to authenticated using (public.has_staff_role(array['admin']))
	with check (public.has_staff_role(array['admin']));

create policy "Published gallery items are public" on public.gallery_items
	for select to anon, authenticated using (is_published);
create policy "Admins manage gallery items" on public.gallery_items
	for all to authenticated using (public.has_staff_role(array['admin']))
	with check (public.has_staff_role(array['admin']));

create policy "Published testimonials are public" on public.testimonials
	for select to anon, authenticated using (is_published);
create policy "Admins manage testimonials" on public.testimonials
	for all to authenticated using (public.has_staff_role(array['admin']))
	with check (public.has_staff_role(array['admin']));

create policy "Site settings are public to read" on public.site_settings
	for select to anon, authenticated using (true);
create policy "Admins manage site settings" on public.site_settings
	for all to authenticated using (public.has_staff_role(array['admin']))
	with check (public.has_staff_role(array['admin']));

create policy "Public may submit new applications" on public.applications
	for insert to anon, authenticated
	with check (status = 'New' and admission_number is null);
create policy "Admissions staff read applications" on public.applications
	for select to authenticated using (public.has_staff_role(array['admin', 'admissions']));
create policy "Admissions staff update applications" on public.applications
	for update to authenticated using (public.has_staff_role(array['admin', 'admissions']))
	with check (public.has_staff_role(array['admin', 'admissions']));
create policy "Admins delete applications" on public.applications
	for delete to authenticated using (public.has_staff_role(array['admin']));

create policy "Staff read student roster" on public.students
	for select to authenticated using (public.has_staff_role(array['admin', 'admissions', 'trainer']));
create policy "Students read their own roster record" on public.students
	for select to authenticated using (auth_user_id = (select auth.uid()));
create policy "Admissions staff create students" on public.students
	for insert to authenticated with check (public.has_staff_role(array['admin', 'admissions']));
create policy "Admissions staff update students" on public.students
	for update to authenticated using (public.has_staff_role(array['admin', 'admissions']))
	with check (public.has_staff_role(array['admin', 'admissions']));
create policy "Admins delete students" on public.students
	for delete to authenticated using (public.has_staff_role(array['admin']));

create policy "Admissions staff manage payments" on public.student_payments
	for all to authenticated using (public.has_staff_role(array['admin', 'admissions']))
	with check (public.has_staff_role(array['admin', 'admissions']));

create policy "Staff read student keys" on public.student_keys
	for select to authenticated using (public.has_staff_role(array['admin', 'admissions', 'trainer']));
create policy "Students read their own key" on public.student_keys
	for select to authenticated using (
		exists (
			select 1 from public.students
			where students.admission_number = student_keys.admission_number
				and students.auth_user_id = (select auth.uid())
		)
	);
create policy "Admissions staff manage student keys" on public.student_keys
	for all to authenticated using (public.has_staff_role(array['admin', 'admissions']))
	with check (public.has_staff_role(array['admin', 'admissions']));
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

create policy "Admissions staff manage student statements" on public.student_statements
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

create policy "Trainers read own results and admins read all" on public.results
	for select to authenticated
	using (public.has_staff_role(array['admin']) or (teacher_id = (select auth.uid()) and public.has_staff_role(array['trainer'])));
create policy "Trainers publish results" on public.results
	for insert to authenticated
	with check (teacher_id = (select auth.uid()) and public.has_staff_role(array['admin', 'trainer']));
create policy "Trainers delete own results and admins delete all" on public.results
	for delete to authenticated
	using (public.has_staff_role(array['admin']) or (teacher_id = (select auth.uid()) and public.has_staff_role(array['trainer'])));
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

create policy "Staff roles are visible to the user or admins" on public.staff_roles
	for select to authenticated
	using (user_id = (select auth.uid()) or public.has_staff_role(array['admin']));
create policy "Admins assign staff roles" on public.staff_roles
	for insert to authenticated with check (public.has_staff_role(array['admin']));
create policy "Admins update staff roles" on public.staff_roles
	for update to authenticated using (public.has_staff_role(array['admin']))
	with check (public.has_staff_role(array['admin']));
create policy "Admins remove staff roles" on public.staff_roles
	for delete to authenticated using (public.has_staff_role(array['admin']));

revoke all on function public.has_staff_role(text[]) from public, anon;
grant execute on function public.has_staff_role(text[]) to authenticated;
grant select on public.courses, public.announcements, public.staff_profiles,
	public.gallery_items, public.testimonials, public.site_settings to anon, authenticated;
grant insert on public.applications to anon, authenticated;
grant select, update, delete on public.applications to authenticated;
grant select, insert, update, delete on public.staff_roles, public.courses,
	public.announcements, public.staff_profiles, public.gallery_items,
	public.testimonials, public.site_settings, public.students,
	public.student_payments, public.student_keys, public.student_key_secrets, public.student_statements,
	public.results, public.trainer_result_log to authenticated;

insert into storage.buckets (id, name, public)
values ('site-assets', 'site-assets', true)
on conflict (id) do update set public = excluded.public;

create policy "Public can read site assets" on storage.objects
	for select to anon, authenticated using (bucket_id = 'site-assets');
create policy "Admins upload site assets" on storage.objects
	for insert to authenticated
	with check (bucket_id = 'site-assets' and public.has_staff_role(array['admin']));
create policy "Admins update site assets" on storage.objects
	for update to authenticated using (bucket_id = 'site-assets' and public.has_staff_role(array['admin']))
	with check (bucket_id = 'site-assets' and public.has_staff_role(array['admin']));
create policy "Admins delete site assets" on storage.objects
	for delete to authenticated using (bucket_id = 'site-assets' and public.has_staff_role(array['admin']));
