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
- Starbase shop: the docked ship is untouchable while its shop is open; the world
  keeps going. Each player has their own money.
- Cutscenes: skipped in co-op (a short banner instead); story stays in solo.
- Phone backgrounded / connection lost: its ship goes ghost (untouchable, not
  firing); 60 s to come back, after that it counts as out.

## Phases

| # | What | Done when |
|---|---|---|
| 1 | Net layer (`Net` autoload, ENet server/client, message codec), headless `ServerWorld` (spawner + stand-in ships + sector flow), puppet mode for Enemy/Asteroid/Pickup, enemy shot replication, hit reports, kills | Server + 2 headless bot clients on the Mac clear sector 3 together; bandwidth and CPU measured; latency/loss simulated |
| 2 | Two real windows on the Mac (one sector, two ships, desktop controls), then two phones on LAN | It plays and feels right at 80-150 ms simulated lag |
| 3 | Bosses + parts, mini-bosses, meteors, mega, starbase/shop, deaths + revive pods, sector loop to 24, game over, co-op score board | Full run with two windows |
| 4 | Lobby: room code (reuses challenge-code style), ready screen, reconnect, background handling | Two phones on mobile data join by code |
| 5 | Server on GCP (VM, firewall UDP, systemd, one process per room, small Node lobby that hands out rooms), health + logs | Room created from a phone on 4G |
| 6 | 2-player balance, playtest builds, store notes (Apple reviewer needs a way to try co-op) | Release |
| 7 | AI PARTNERS (Yaniv 11/11, "can wait for later"): bot pilots that fill a room when no human is around. Each bot rolls random traits (aggressiveness, greed for pickups, caution, skill) that drive how it flies, what it shoots and what it grabs; it docks at the starbase, sometimes stays a few seconds after the player leaves, and buys upgrades with its own money. Runs on the server as a third kind of seat (the headless NetBot is the starting point; it needs the real Player/shop state instead of a stand-in). Also what the Apple reviewer can play with. | A solo player can start co-op and get a believable partner |

Effort: phase 1-2 about a week, the rest 3-5 weeks.

## Files (planned)
`scripts/net/Net.gd` (autoload), `scripts/net/Proto.gd` (codec), `scripts/net/ServerWorld.gd`
+ `scenes/net/ServerWorld.tscn`, `scripts/net/NetClient.gd` (proxies, interpolation, partner),
`scripts/net/PartnerShip.gd`, tests `scenes/tools/NetLoopTest.tscn` (server + bots in one process).
