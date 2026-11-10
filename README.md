# Muraga Technical Training Institute Website

Website and student portals for **Muraga Technical Training Institute (MTTI)** - *Innovation & Excellence*.

## What is in this repository

| Path | Description |
|---|---|
| `index.html` | The website (home, about, courses, apply, news, gallery, management, contact) and the portals |
| `assets/styles.css` | Styles |
| `assets/app.js` | Site logic, admin panel, portals, Excel and PDF tools |
| `assets/supabase-backend.js` | Supabase Auth, database, realtime and Storage adapter |
| `assets/supabase-config.js` | Public Supabase project URL and anon key |
| `supabase/migrations/20261110000000_initial_schema.sql` | Database tables, row-level security and Storage policies |
| `supabase/migrations/20261110000001_auth_student_link.sql` | Auth-link upgrade for existing databases and student key access |
| `supabase/migrations/20261110000002_student_fee_transactions.sql` | Student-visible payment ledger and backfill from existing fee statements |
| `supabase/migrations/20261110000003_student_portal_allowlist.sql` | Enables student portal access only for records imported from the Admin CSV |
| `supabase/migrations/20261110000003_student_portal_allowlist.sql` | Restricts student portal access to records enabled by the Admin CSV import |
| `supabase/functions/student-auth/index.ts` | Secure student account creation and admission-number sign-in endpoint |
| `supabase/seed.sql` | Unpublished demo content and optional initial admin role assignment |

## Features

- Multi-page layout with hero slider, dropdown menu and animations
- Courses by department and campus (Main Campus and Kaare Campus), Level 4-6 with KCSE entry requirements
- Online application form with a downloadable PDF application slip
- Admin panel: courses, announcements, gallery, management, testimonials, vision and mission, values, fee structure, contacts, social links
- Admin CSV exports for the complete student roster and payment transaction ledger
- Supabase Auth login for **Students** and **Admin / Staff**, with role-based portals
- Role-based portals: **Admin**, **Admissions**, **Trainer**, **Student**
- Trainers publish results (single entry or Excel upload) with competency levels: Mastery, Proficient, Competent, Not Yet Competent
- Admins can import the student CSV from **Student Data CSV**; only imported rows are enabled for portal access. Admissions can also import Excel/CSV and record fee payments
- Student results and fee statements are end-to-end encrypted; students also see their RLS-protected payment ledger and calculated balance

## Configure Supabase

The site uses Supabase Auth for staff and student accounts, PostgreSQL for site and portal data, and the `site-assets` Storage bucket for public images and documents.

1. Create a Supabase project.
2. In **Project Settings > API**, copy the Project URL and the public `anon` key into `assets/supabase-config.js`. These values are safe for browser use; never put a `service_role` key in this file.
3. Open **SQL Editor** and run all migration files in timestamp order: `20261110000000_initial_schema.sql`, `20261110000001_auth_student_link.sql`, `20261110000002_student_fee_transactions.sql`, then `20261110000003_student_portal_allowlist.sql`. These create/update tables, row-level security policies, the Storage bucket, Realtime publication entries, the student payment ledger, and CSV-controlled portal access. The later migrations upgrade projects that already ran earlier schema versions.
4. Deploy the `student-auth` Edge Function with the Supabase CLI: `supabase login`, `supabase link --project-ref <project-ref>`, then `supabase functions deploy student-auth`. The function uses Supabase's server-side `SUPABASE_SERVICE_ROLE_KEY`; never put this secret in the website.
5. In **Authentication > Users**, invite or create your first administrator.
6. Open `supabase/seed.sql`, replace `replace-with-admin-email@example.org` with that Auth user's email, then run the file in **SQL Editor**. It inserts unpublished demo content and assigns that existing user the `admin` role. It does not create an Auth account.
7. Sign in to the site's staff portal with that Auth account. Admins can assign staff roles using the user's UUID from **Authentication > Users**.

Demo courses, announcement, staff profile, testimonial, and application are marked as sample content. The site hides the unpublished public-content rows; remove the sample application after testing if you do not need it.

Import the official student list using **Admin > Student Data CSV > Open Student Import**. Only students in that CSV are enabled for portal access; manually enrolled rows remain disabled until included in the CSV. Include the `Email Address` column so each student can create an account. Rows without an email are imported but cannot create an account until Admissions adds one. Students enter their admission number, matching roster email, and an initial password, then sign in using their admission number or exact unique full name and password. If names are duplicated, they must use the admission number. They still enter their admission number and PIN to decrypt results and fee statements. Payment balances and transactions remain protected by RLS.

The old hard-coded Admin password is no longer used; staff access is controlled by Supabase Auth and `staff_roles`.

The application form accepts anonymous submissions, while private records are protected by row-level security. Public Supabase URL and anon key only belong in frontend code. Keep database passwords and service-role keys server-side.

## Preview locally

Serve the site over HTTP so Supabase Auth can use the local origin:

```bash
python3 -m http.server 8000
```

Open `http://localhost:8000`. Add the local URL and your deployed site URL under **Authentication > URL Configuration > Redirect URLs** in Supabase. An internet connection is required for the Supabase, PDF and Excel libraries.

## Publish the static pages with GitHub Pages

1. Push this repository to GitHub (see below).
2. Repository **Settings > Pages**.
3. Source: **Deploy from a branch**, branch **main**, folder **/ (root)**, then **Save**.
4. After a minute the site is live at `https://<your-username>.github.io/<repository-name>/`.

## Upload to GitHub

**Using the website:** create a new repository on github.com, click **Add file > Upload files**, drag in everything from this folder (keep the folders), then **Commit changes**.

**Using Git:**
```bash
git init
git add .
git commit -m "Add MTTI website"
git branch -M main
git remote add origin https://github.com/<your-username>/<repository-name>.git
git push -u origin main
```

## Excel templates

The templates are generated inside the portals (Trainer: results; Admissions: student import). Columns:

- Results: `Admission Number, Student Name, Unit, Assessment, Marks, Competency`
- Students: `Admission Number, Student Name, Email, Phone, Course, Campus, Total Fees, Amount Paid`

## Credits and rights

The MTTI logo and photographs belong to Muraga Technical Training Institute. The TVETA, TVET CDACC and Kenya Vision 2030 logos belong to their respective owners and are shown to identify partners. Add a licence of your choice before making the repository public.

## Security note

Staff and student identities use Supabase Auth. Keep the Supabase service-role key and database credentials out of browser code. Student results and fee statements remain encrypted for PIN-based decryption; payment ledger rows rely on row-level security rather than end-to-end encryption.
