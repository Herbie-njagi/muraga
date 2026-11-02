# Muraga Technical Training Institute Website

Website and student portals for **Muraga Technical Training Institute (MTTI)** - *Innovation & Excellence*.

## What is in this repository

| Path | Description |
|---|---|
| `index.html` | The website (home, about, courses, apply, news, gallery, management, contact) and the portals |
| `assets/styles.css` | Styles |
| `assets/app.js` | Site logic, admin panel, portals, Excel and PDF tools |

## Features

- Multi-page layout with hero slider, dropdown menu and animations
- Courses by department and campus (Main Campus and Kaare Campus), Level 4-6 with KCSE entry requirements
- Online application form with a downloadable PDF application slip
- Admin panel: courses, announcements, gallery, management, testimonials, vision and mission, values, fee structure, contacts, social links
- Login page for **Students** (admission number) and **Admin / Staff** (role-based, with an admin password step)
- Role-based portals: **Admin**, **Admissions**, **Trainer**, **Student**
- Trainers publish results (single entry or Excel upload) with competency levels: Mastery, Proficient, Competent, Not Yet Competent
- Admissions can import enrolled students from Excel and record fee payments
- Student results and fees are end-to-end encrypted; students view them with their admission number

## Important: where the portals run

The portals, admin panel and database features were built for the **claude.ai artifact runtime** (`window.claude` database, file storage, sign-in and downloads). 

- **On GitHub Pages or any plain web host, the public pages display, but the admin panel and portals show as unavailable and nothing can be saved.**
- To run the full system on your own hosting you need a backend with real sign-in and a database (for example Firebase or Supabase) and the data calls in `assets/app.js` replaced with it. The encryption code (`mkKeys`, `seal`, `unseal`) is plain Web Crypto and can be reused as is.

## Preview locally

Open `index.html` in a browser (an internet connection is needed for the PDF and Excel libraries).

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
- Students: `Admission Number, Student Name, Phone, Course, Campus, Total Fees, Amount Paid`

## Credits and rights

The MTTI logo and photographs belong to Muraga Technical Training Institute. The TVETA, TVET CDACC and Kenya Vision 2030 logos belong to their respective owners and are shown to identify partners. Add a licence of your choice before making the repository public.

## Security note

The admin password step stores only a salted hash in `assets/app.js`, but a short password can still be cracked offline by anyone who can read the code. Change it before publishing, and use a backend with real accounts for production.
