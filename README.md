# Hackathon Arena

Live hackathon judging, team checklists and an animated projector leaderboard. One page, no sign-up. Data and live updates run on Supabase; the site is hosted on GitHub Pages.

## Go live

1. **Database.** In Supabase, open SQL Editor → New query, and run `supabase/01-setup.sql`, then `supabase/02-end-and-cleanup.sql`.
2. **Key.** In Supabase, open Project Settings → API Keys and copy the **anon / publishable** key. Paste it into `index.html` where it says `PASTE_YOUR_ANON_KEY_HERE`. (This key is meant to be public. Never paste the `service_role` / secret key.)
3. **Publish.** Create a public GitHub repo, upload `index.html`, then open Settings → Pages → Source: "Deploy from a branch" → `main` / root → Save. The site is live at `https://<your-username>.github.io/<repo>/` within a couple of minutes.

## How it works

- **Create** an event: pick a theme, add branding, teams, objectives and judging questions, and choose a host password. You get a 5-character event code.
- **Join** with the code as a team, a judge, or the leaderboard screen. No accounts.
- **Host tools** (Join → "Host tools"): event code + host password to edit the event or clear scores.

Host passwords are stored hashed in a table the website can't read, and edits are checked inside the database.

## Ending and cleanup

- **End event** (host tools) freezes scores and switches the leaderboard to final results. Judges and teams see the final standings and can't make changes. Hosts can reopen it.
- **Delete event now** removes an ended event and all its data immediately.
- A nightly job (3am UTC) deletes events that ended more than 7 days ago, and any event with no activity for 30 days.
