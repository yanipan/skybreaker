# Skybreaker 1.0.2: pilot names, leaderboards, friend challenges

Status: BUILT 6 Nov 2026 and folded into 1.0.1 (Yaniv: "do the leaderboard and publish all"). Branch v1.0.2 retired.
Server: the existing SiteGround host (englishapp.shimonster.com/skybreaker), same DB as the
play stats (`sb_*` tables). No new server. Online co-op (Nakama on a VM) is a later decision,
driven by the stats.

## Decisions (defaults, change if Yaniv says otherwise)
- Identity = the existing random install id (Telemetry.player_id). No account, no password.
- Default name `Pilot-NNNN`; player can pick a name the first time a score qualifies, or in Settings.
- Names: 3-16 chars, `A-Z a-z 0-9 _`, unique case-insensitively, server-side bad-word filter.
- Leaderboards: ALL TIME and THIS WEEK (Mon-Sun UTC), top 50 + "your rank".
  One shared board for iOS and Android.
- Score submitted at game over and at run end (sector 20 clear). Best per player per board.
- Challenge = a full run from sector 1 with a fixed wave seed. The challenger's score is the
  target. Shared as a 6-char code (copied to the clipboard, "send it to a friend"); a tap-to-open
  link needs universal links / app links, later.

## Phase 1: server (about 0.5 day)
- Tables: `sb_names(player_id PK, name, name_lc UNIQUE, status ok|banned, updated_at)`,
  `sb_scores(player_id, board_week, score, sector, run_id, created_at, flagged)`,
  `sb_challenges(code PK, player_id, seed, score, sector, created_at)`,
  `sb_challenge_runs(code, player_id, score, sector, created_at)`.
- Endpoints (X-SB-Key): `name.php` (check / set), `score.php` (submit), `leaderboard.php`
  (board=all|week, top 50 + me), `challenge.php` (create / get / results).
- Filter: normalised name (lowercase, leetspeak 4->a 3->e 1->i 0->o 5->s 7->t @->a $->s,
  repeats collapsed) checked against a word list (EN + HE translit + ES/FR/DE/PT/RU translit basics)
  and reserved words (admin, apple, google, shimonster, skybreaker...).
- Plausibility: reject score if it is above a per-sector ceiling or if the run has no
  matching sector_complete events in sb_events; flagged rows hidden, not deleted.
- Admin in stats.php: list names, rename to Pilot-NNNN, ban.

## Phase 2: seeded waves (about 0.5 day)
- New autoload `GameRng` with separate RandomNumberGenerator streams: `waves` (EnemySpawner
  timing, types, positions, asteroids, boss pattern rolls) and `combat` (enemy fire jitter, drops).
  Visual effects (explosions, starfield, parallax) stay on the global RNG.
- Seed per sector = hash(run_seed, sector). Normal runs get a random run_seed; challenges use the
  challenge seed. Saved in the run save so CONTINUE keeps it.
- Test: two simulated runs with the same seed and different player inputs produce the same
  spawn log for the first N waves of each sector.

## Phase 3: game UI (about 1-1.5 days)
- Start screen: LEADERBOARD button (tabs ALL TIME / THIS WEEK, my rank highlighted) and
  ENTER CHALLENGE CODE.
- Game over / victory screen: score, rank, "NEW BEST", CHALLENGE A FRIEND (creates the code,
  copies it, shows it big).
- Name prompt (first qualifying score, and Settings > PILOT NAME): on-screen keyboard field,
  server validation message ("taken" / "try another name").
- Challenge HUD: target score in the corner; result screen "You beat NAME by N" / "N short".
- Offline: everything degrades to "leaderboard unavailable", runs never block on the network.

## Phase 4: privacy + stores (about 0.5 day)
- Policy: add pilot name + public leaderboard paragraph.
- Apple App Privacy: add User ID (screen name), not linked to identity, not tracking.
  Guideline 1.2 user content: filter + admin removal + report contact in the policy.
- Play data safety: add "User IDs", collected, not shared, optional.

## Phase 5: verify + ship (about 0.5 day)
- Headless tests: name rules + filter (server, via curl suite), seeded wave determinism, score
  submit queue offline/online, challenge round trip.
- Two real phones: create a challenge on one, play it on the other.
- TestFlight + Play internal, then production.

Total: about 3-4 working days.
