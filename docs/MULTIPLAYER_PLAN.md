# Skybreaker co-op multiplayer: plan (11/11/2026)

Decisions (Yaniv, 11/11): **server-authoritative** (headless Godot on a cloud VM, a
player who drops or backgrounds does not end the run), **own lives with revive**,
hosted on the **existing personal GCP project**.

## Split of authority

| Server owns (one headless Godot process per room) | Each phone owns |
|---|---|
| EnemySpawner (unchanged), enemies, bosses, mini-bosses, asteroids, megas | Its own ship: movement, firing, its own shots |
| Enemy fire: spawns every enemy bullet / beam and tells both phones | Damage it TAKES (own ship vs locally flown enemy bullets) |
| Enemy HP: applies the hits phones report, decides kills, who gets the score | Money, upgrades, shop, shield, torpedoes, lives (GameState as today) |
| Pickups: spawns them, first phone to claim one gets it | HUD, controls, effects, sounds |
| Sector flow: start, boss gate, sector end, warp, game over | Rendering the partner ship (cosmetic, from its state stream) |

Why: the single-player code (Player, Bullet, Beam, Missile, Torpedo, shop, HUD,
GameState) keeps working as is on the phone; the shooter sees instant hits on what
it sees; the server only needs the world simulation, which already runs headless
(PerfProbe 1.5 ms/frame on sector 24). Co-op only, so trusting the phone for its
own ship is fine; the co-op leaderboard is separate from the ranked solo board.

## Protocol (ENet over UDP, server has a public IP, no NAT traversal)

Server -> phones
- `spawn` (reliable): id, kind (enemy/boss/asteroid/mega/pickup), type and every
  random roll the phone needs to build the same object (size, alt weapon, drift...).
- `snap` (unreliable, 20 Hz): id + position (+ rotation, hp fraction) for live entities.
  Phones show entities ~100 ms behind, interpolated.
- `shot` (reliable): one enemy bullet / beam / mine with its full launch state and,
  for homing shots, which ship it chases. Phones fly the shots themselves.
- `kill` / `despawn` (reliable): id, killer, reward. Phone plays the death effects.
- `sector`, `warp`, `alert`, `game_over` (reliable): flow events.
- `partner` (unreliable, 20 Hz): the other ship's position, weapon, power, firing, alive.

Phones -> server
- `ship` (unreliable, 30 Hz): position, weapon, power level, firing, alive, shield.
- `hits` (reliable, batched per tick): {entity id: damage} from this phone's shots.
- `claim` (reliable): pickup id. `down` / `revive` / `ready` / `leave`.

## Game rules for two

- Enemy aim, chase (Reaper), beam tracking (Beamer), homing: target the NEAREST
  living ship (server stand-in nodes in group "player" carry the phone positions).
- Scaling with 2 ships: enemy HP x1.6, boss HP x1.8, waves +1 enemy (tune in playtest).
- Own lives: a ship that loses its last life drops a REVIVE POD; the partner flies
  through it to bring it back with 1 life. Both out = run over.
- No pause: the pause button opens the menu but the world keeps going.
- Starbase shop: SUPERSEDED 11/11 by "Co-op shop" below (one enters = both enter,
  the world freezes, play resumes when both have left). Each player has their own money.
- Cutscenes: skipped in co-op (a short banner instead); story stays in solo.
- Phone backgrounded / connection lost: its ship goes ghost (untouchable, not
  firing); 60 s to come back, after that it counts as out.

## Phases

| # | What | Done when |
|---|---|---|
| 1 | Net layer (`Net` autoload, ENet server/client, message codec), headless `ServerWorld` (spawner + stand-in ships + sector flow), puppet mode for Enemy/Asteroid/Pickup, enemy shot replication, hit reports, kills | Server + 2 headless bot clients on the Mac clear sector 3 together; bandwidth and CPU measured; latency/loss simulated |
| 2 | Two real windows on the Mac (one sector, two ships, desktop controls), then two phones on LAN | It plays and feels right at 80-150 ms simulated lag |
| 3 | Bosses + parts, mini-bosses, meteors, mega, starbase/shop, deaths + revive pods, sector loop to 24, game over, co-op score board | Full run with two windows |
| 4 | Lobby: PLAY WITH A FRIEND (6-char code + QR/invite link) and PLAY NOW (match a human for ~10 s, else an AI partner on the phone), reconnect, background handling. See "Finding a partner". | Two phones on mobile data join by code; a lone player gets a bot |
| 5 | Server on GCP (VM, firewall UDP, systemd, one process per room, small Node lobby that hands out rooms), health + logs | Room created from a phone on 4G |
| 6 | 2-player balance, playtest builds, store notes (Apple reviewer needs a way to try co-op) | Release |
| 7 | AI PARTNERS (Yaniv 11/11, "can wait for later"): bot pilots that fill a room when no human is around. Each bot rolls random traits (aggressiveness, greed for pickups, caution, skill) that drive how it flies, what it shoots and what it grabs; it docks at the starbase, sometimes stays a few seconds after the player leaves, and buys upgrades with its own money. Runs on the server as a third kind of seat (the headless NetBot is the starting point; it needs the real Player/shop state instead of a stand-in). Also what the Apple reviewer can play with. | A solo player can start co-op and get a believable partner |

Effort: phase 1-2 about a week, the rest 3-5 weeks.

## Progress (11/11)

| Phase | State |
|---|---|
| 1 net layer, room server, puppets, bots | done |
| 2 real game screen in a room (two windows on the Mac) | done |
| 3a bosses, mini-bosses, breakable parts | done (bots: Iron Tortoise killed at 80 ms / 3% loss) |
| 3b shared shop | done (bots + two real windows) |
| 3c down / rescue pod / return next sector / both down = over | done (bots: rescue, both down; two real windows) |
| 3d full run to sector 24 | done with bots 11/11: 24 sectors, all 8 boss types incl. the Herald + Skybreaker finale, won=true, 0 script errors, 15 min at duration_mul 0.35 (that run has no mini-bosses, shops or megas: they sit past the shortened sector end; mini-boss checked separately on sector 6 at full length) |
| 3e co-op result screen (both scores at the end of a run) | not started; goes with the lobby UI in phase 4 |
| 4 lobby (code, QR, Play now) | not started |
| 5 GCP | not started |
| 6 balance for two, store notes | not started |
| 7 AI partners | not started |

Open design question: shop timer for matched games (proposal 30 s after the first player is ready, none with friends). The server already has it as `--shop_timer`, off by default.

## Files (planned)
`scripts/net/Net.gd` (autoload), `scripts/net/Proto.gd` (codec), `scripts/net/ServerWorld.gd`
+ `scenes/net/ServerWorld.tscn`, `scripts/net/NetClient.gd` (proxies, interpolation, partner),
`scripts/net/PartnerShip.gd`, tests `scenes/tools/NetLoopTest.tscn` (server + bots in one process).

## Co-op shop (Yaniv 11/11: "when one enters both enter, when one leaves he waits for the other")

The world FREEZES while the shop is open, exactly like single-player. That is what
makes "both enter" cheap and fair: nobody is shot while browsing.

Flow
1. Either ship touches the starbase. That phone pauses at once (as today) and sends
   `DOCK starbase_id`. The server checks the starbase is unused, freezes the world
   (spawner, enemies, timers, its clock) and sends `SHOP_OPEN` to both.
2. The other phone pauses on `SHOP_OPEN` and its shop slides in with
   "<NAME> DOCKED AT THE STARBASE". It may have played up to ~0.2 s longer than the
   server: damage taken in that gap stands, and the ship gets 1 s of shield on resume.
3. Each player shops with their own money. A strip shows the partner: name,
   SHOPPING / READY, and their purchases as they happen ("VIPER bought SHIELD +1").
4. LEAVE means READY. The first one out sees "WAITING FOR <NAME>..." with a
   BACK TO SHOP button (changing your mind is allowed until both are ready).
5. Both ready -> server sends `SHOP_CLOSE`; both phones run the existing
   GET READY 3-2-1 (3.2 s); the server unfreezes when it ends.

Rules for the awkward cases
- Timer: with a FRIEND (private room) no timer. In a MATCHED game, once one player is
  ready the other gets 30 s (shown to both), then is made ready. Tunable.
- Partner disconnected / app in background: counts as ready after 10 s, so nobody is
  held hostage. If they come back while the shop is open they rejoin it.
- Partner is down (no lives left): they enter the shop too and can spend; they stay
  down afterwards unless revived (pod). Open idea: sell a RESCUE in the shop.
- Only one ship left in the run: shop opens for that one, no waiting.
- One starbase = one visit for the pair.
- AI partner (phase 7): shops 2-8 s by its traits, sometimes lingers up to ~4 s after
  the human is ready, buys upgrades with its own money.

Technical notes
- The server clock stops during the freeze, phone clocks do not: on `SHOP_CLOSE`
  each phone must RESET its clock estimate and snapshot buffers (NetClient._offset,
  _buf), or puppets and held shots jump.
- New messages: DOCK, SHOP_OPEN, SHOP_BUY (relay for the partner strip), SHOP_READY
  (true/false), SHOP_CLOSE. Starbase becomes a replicated entity.

## Finding a partner (Yaniv 11/11: friend by QR or typed code; "Play now" = a player or a bot)

Play with a friend
- Host taps PLAY WITH A FRIEND -> a room is created -> the screen shows a 6-character
  code (same style as challenge codes, no 0/O/1/I/L), a QR and a COPY INVITE button.
- The QR and the invite are a LINK, e.g. https://shimonster.com/skybreaker/join/AB3K9X.
  Scanned with the phone's own camera: game installed -> opens straight into the
  room; not installed -> a page with the code and the store buttons (every invite is
  also an install link).
- DECIDED by Yaniv 11/11: scanning happens IN THE GAME, in the game's own look
  (branded scanner screen, branded QR with the logo). The QR still carries the
  invite LINK, so the phone's normal camera also works and a friend without the
  game lands on the store page.
- Cost of the in-game scanner: camera permission prompt on both platforms, store
  privacy declarations, and a QR reader. Found 11/11 (web, NOT tried): Godot's
  CameraServer docs now list Android and iOS (iOS needs the camera module enabled
  in the export); a community "Godot QR plugin" generates QRs and reads them from an
  Image (Android build listed for Godot 4.6, iOS build for 4.5), so live scanning
  = feeding it camera frames. Needs a spike on two real phones before it is promised.
  Typing the code always works as the fallback.
- The friend can always just type the code (JOIN WITH CODE).
- Both in the room -> names shown -> 3 s countdown -> sector 1.
- Codes live 10 minutes or until the run starts; join attempts are rate-limited.
- NOT VERIFIED: opening the game from a link needs an Android intent filter and an
  iOS associated-domain entitlement plus a small native hook in the Xcode project.
  I have not tried this with Godot 4.6. Fallback that needs no native code: the link
  opens the web page, which shows the code to type.

Play now
- PLAY NOW -> "SEARCHING FOR A PILOT..." for up to ~10 s. Another human waiting on the
  same game version -> paired. Nobody -> an AI partner joins.
- Bots, DECIDED by Yaniv 11/11 "for now": 50% of bot partners are DISGUISED (a
  human-looking pilot name, no tag), 50% are LABELLED (callsign + small AI tag,
  "AI wingman VIPER joined"). Treat it as an experiment: log which kind each game
  had (telemetry) so the two groups can be compared (session length, runs per
  day, quits). Either kind stays off the leaderboards and cannot be name-reported.
- Only same protocol version is matched (stores roll out at different times);
  an old build gets "Update to play co-op".
- If a human partner leaves and does not return within the reconnect window, an AI
  takes over their seat so the run goes on.
- No free chat. Pre-made messages instead (see below).

Where bot games run: ON THE PHONE, not in the cloud
- Measured 11/11 (M5 Max, sector 18, unoptimized): one room = ~360 MB RAM and 13-17%
  of one core. A cloud vCPU is slower (not measured yet), so a small VM holds only a
  handful of rooms.
- Early on almost every PLAY NOW will end with a bot. Paying a cloud room for each of
  those is the wrong way round. A bot game runs the same server code inside the phone
  (loopback): no server cost, no lag, works offline.
- Cloud rooms are then only for two humans (and for a bot that replaces a leaver).
- RISK to validate first: server and client in one process share the autoloads
  (GameState, GameRng). The loop tests deliberately used separate processes.
- Server optimisation still to do: the headless room loads every texture and sound
  (most of the 360 MB) and ticks at 60 Hz; a 30 Hz tick and skipping art should cut both.

Run length (open question)
- DECIDED by Yaniv 11/11: the v1 proposal below.
- A full run is 24 sectors, roughly 45-60 minutes. v1 proposal: co-op starts at
  sector 1 and goes as far as the pair gets, with a "KEEP GOING?" prompt after each
  boss. Short "one act" matches (about 10 minutes, ending on a boss) are a later option;
  they need a starting loadout per act because gear is earned inside a run.

## Later (remembered, not scheduled)
- PRE-MADE MESSAGES (Yaniv 11/11, "don't do that now just remember it"): a small icon
  that opens a few canned messages / emotes with a face, Clash Royale style
  (e.g. Thanks, Help, Nice, Let's shop). Safe for a 13+ audience, no moderation.
- AI partners with traits: phase 7 above.
- Gift credits to the partner in the shop.
- A human joining a bot game in its first sectors (taking the bot's seat).
