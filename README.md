# Hackathon Arena

Live hackathon judging, team checklists and an animated projector leaderboard. One page, no sign-up. Data and live updates run on Supabase; the site is hosted on GitHub Pages.

## Go live

1. **Database.** In Supabase, open SQL Editor → New query, and run the files in `supabase/` in order: `01-setup.sql`, `02-end-and-cleanup.sql`, `03-inactive-7-days.sql`, `04-judge-codes.sql`, `05-keep-event.sql`, `06-inactive-14-days.sql`, `07-timer-and-reveal.sql`, `08-judges.sql`.
2. **Key.** In Supabase, open Project Settings → API Keys and copy the **anon / publishable** key. Paste it into `index.html` where it says `PASTE_YOUR_ANON_KEY_HERE`. (This key is meant to be public. Never paste the `service_role` / secret key.)
3. **Publish.** Create a public GitHub repo, upload `index.html`, then open Settings → Pages → Source: "Deploy from a branch" → `main` / root → Save. The site is live at `https://<your-username>.github.io/<repo>/` within a couple of minutes.

## How it works

- **Create** an event: pick a theme, add branding, add teams and objectives, describe what teams are building (the brief), add and judging questions, and choose a host password. You get a 5-character event code.
- **Join** with the code as a team or the leaderboard screen. No accounts.
- **Judges** also need the event's private 6-character judge code, shown only in Host tools. Scores are only saved when the judge code checks out.
- **Host tools**: open from the leaderboard, the role screen, or Join → "Host tools". The host password is asked for every time, kept only while you're inside Host tools in that browser tab, and never saved on the device. Leaving Host tools locks it again, so a shared projector laptop stays safe.

Host passwords are stored hashed in a table the website can't read, and edits are checked inside the database.

## Judges

Hosts never set judges up in advance; the only judging setup is the questions. A judge appears in **Host tools → Judges** as soon as they sign in with the judge code, and every team on the leaderboard gets one judge box per judge in the event (before anyone joins, it says "No judges yet"). From the Judges tab the host can:

- **Rename** a judge (fixes the name on their scorecards and team results).
- **Remove** a judge: their scorecards are deleted, their box comes off the leaderboard, their phone is signed out, and they can't sign back in.
- **Let back in** a removed judge.

## Ending and cleanup

- **End event** (host tools) freezes scores and switches the leaderboard to final results. Judges and teams see the final standings and can't make changes. Hosts can reopen it.
- **Delete event now** removes an ended event and all its data immediately.
- A nightly job (3am UTC) deletes events that ended more than 7 days ago, and any event with no activity for 14 days.
- Hosts see an "Auto-deletes in…" countdown in Host tools with a **Keep event** button that restarts the deletion timer. When an event is within 2 days of deletion, the host gets a popup, and if one of their events has already been deleted they're told the next time they open the site.

## Countdown timer

Host tools → **Start timer**: pick 15 min to 2 hours or type any number of minutes, and give it a label. It shows live on every team screen and the leaderboard, synced to the database clock. **Timer controls** lets the host pause, resume, add or remove 5 minutes, or reset. It turns amber under 5 minutes, pulses red under 1 minute, and flashes "Time's up" at zero.

## Hidden scores and the reveal

Scores are hidden until the host reveals them. The leaderboard and team screens only show how many judge scorecards are in; the host can preview totals in Host tools. **Reveal scores** plays a 3-2-1 countdown on the leaderboard, flips each team's score in from last place to first, and crowns the winner. Every team screen gets its own reveal with its rank, total, and average score per judging question (strongest and weakest highlighted), then keeps a results panel.

## The brief

Create and Edit have a **Brief** step: an optional "Building for" client name and up to 4 deliverables, each with a short name, a one-line description and the teams that build it (all teams by default). They appear in a strip at the top of the leaderboard so anyone in the room can see what teams are building. Leave it empty and the strip is hidden.

## Leaderboard style

Create and Edit start with **Look**: pick the theme and the leaderboard style.

- **Classic** (default): clean rows and scores.
- **Arcade**: slanted power bars, a live feed of every event, and animated objective hits (a light streak hits the next block, which ignites with sparks), plus streaks, milestone stamps, overtake arrows and judge markers. Each team's row animates on its own, so bursts of updates play at the same time; updates to the same team play in order and speed up if they pile up. The feed shows the newest 8 events.

In both styles, objective blocks fill from the left no matter which objectives a team ticks.

## Sound

Music and sound effects are generated live in the browser (no audio files) and play **only on the leaderboard screen**, so team and judge phones stay silent.

- **Two lofi soundtracks, kept low-key so they sit under the room.** *Classic*: warm, jazzy electric-piano chords (76 bpm). No melody instrument, just chords, bass and beat. *Arcade*: mellow, filtered chiptune keys (82 bpm). No lead melody, just keys, a soft arpeggio, bass and beat. Both have a lazy swing, a soft muffled beat, light vinyl crackle and a drum-free breather so they don't feel like a short loop. By default the profile follows the leaderboard style; you can pin either one.
- **Arcade-style effects:** objective cleared (climbs in pitch as hits chain into combos), milestone, streak, judge scorecard, build submitted, overtake / new leader, the last 10 seconds of the countdown, time's up, and the reveal (a building riser during the race, then a winner fanfare). Music ducks under big moments. Repeated effects are rate-limited so bursts stay exciting instead of noisy.
- **Host tools → Sound** (its own tab): sound on/off, profile (Auto / Classic / Arcade), Music and Effects volume, and extras (combo pitch climb, countdown ticks, reveal riser and fanfare). "Try it on this device" plays the music and every effect on the phone or laptop you're holding. Changes save automatically and reach the projector within a second or two. The faders are exact: Music at 0 means no background music at all (only effects when something happens), Effects at 0 means no effects, and both at 0 is silent. The basics are also on Create/Edit → Look.
- **On the projector:** browsers need one tap before audio can play, so the leaderboard shows an **Enable sound** button (any tap on the screen also works). The same button mutes or unmutes that screen.
