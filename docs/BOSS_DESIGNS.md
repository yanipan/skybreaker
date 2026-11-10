# Skybreaker boss designs (10/11/2026)

Today every boss is the same machine: one sprite, one rectangle hitbox, one HP bar,
drift left/right, cycle 3 bullet patterns, faster in 3 HP phases. The only variety
is the pattern list (plus Archon's beam, Herald's homing). This doc proposes what
makes bosses feel *different*: bodies made of parts, monsters that move like
animals, bosses that change form, and fights built around the fire wheel.

Design rules for a portrait phone with a thumb on the ship:
- Every big attack is telegraphed (flash, warning line, wind-up sound) at least 0.8 s ahead.
- The player's ship must never be trapped with no gap; walls always leave a lane.
- Each fight should make at least one weapon the *smart* choice (phaser, beam, missiles,
  torpedo), so the fire wheel matters.
- 60-120 s per fight. Parts give mid-fight rewards (money pops) so long fights feel paid.
- No control hijacking (inverted steering feels like a bug on touch).

---

## A. Engine pieces needed (build once, reuse everywhere)

| Piece | What it is | Notes |
|---|---|---|
| **BossPart** | Area2D child of a boss with its own HP, sprite, hitbox, armor, `on_destroyed` | Joins group `enemies` and has `take_damage`, so Bullet / Beam / Missile / Torpedo / HitCheck work with no changes. Missiles naturally spread over parts. |
| **Core shield rule** | Core takes 0 or reduced damage while listed parts live | Show "shield" shimmer on the core; HP bar shows parts as notches. |
| **Form / phase script** | Boss data = list of forms: sprite, hitbox, movement mode, pattern list, HP threshold or timer | Shapeshift = 0.6 s morph (flash, scale tween, invulnerable), then the next form. |
| **Movement modes** | `drift` (today), `hover_track` (follow player x slowly), `dash` (telegraphed charge), `orbit`, `teleport`, `trail` (segments follow head's path history), `enter_bottom` | `trail` is the worm/serpent engine. |
| **New attack primitives** | bullet wall with a gap, rotating laser arm (line hazard), gravity well (pulls ship + bends bullets), minion launch (any Enemy.Type), mine field, reflector (returns phaser shots), slam column (telegraphed vertical strike) | Most reuse EnemyBullet / EnemyBeam / Enemy spawns. |
| **Multi-bar HP UI** | Main bar + small bars per named part; twin bosses share one bar | Existing bar rides under the boss, keep that. |

Estimate: framework 1-2 days of work, each boss after that S = half a day, M = 1 day, L = 2 days, plus art.

---

## B. Multi-part bosses

**1. DREADNOUGHT "IRONCLAD CHOIR"** (M) — a battleship wider than the screen, scrolls in from the top.
4 turrets + 2 engine pods + bridge. Turrets each have their own pattern (aimed, fan, shell, beam).
Engines dead = it stops strafing. Bridge only opens when engines are down.
Phase 2: hull snaps in half, two halves drift apart and each keeps its surviving turrets.
*Counterplay:* missiles shine (many targets), torpedo cracks a turret cluster.

**2. SERPENT "VORM, THE SPINE OF NIGHT"** (L, space monster) — 12-16 armored segments following
the head along a sine path that winds across the whole screen, sometimes looping back past the ship.
Segments are armored (chip damage), the glowing tail is the weak point. Killing a middle segment
cuts the worm in two: the back half grows a new head (max 3 worms).
*Counterplay:* beam rakes along the body; positioning to reach the tail.

**3. HYDRA "THE THREE MOUTHS"** (M, monster) — a central body with 3 heads on long necks (drawn
lines). Cut a head and it regrows as two unless you hit the exposed stump within 5 s.
Max 5 heads. Each head breathes a different element: spark spiral, acid shells, homing spit.
*Counterplay:* torpedo the stump to cauterise it.

**4. ORBITAL RING "HALO WARDEN"** (M) — a core inside a ring of 8 shield plates that rotates.
Shoot through the moving gaps; plates are breakable but regrow after 10 s. Phase 2 the ring
counter-rotates in two layers; phase 3 the plates detach and fly at you as blades.
*Counterplay:* phaser timing through gaps, missiles curve around plates.

**5. CARRIER "MATRIARCH"** (M) — a long carrier with 3 hangar bays that launch existing enemy
types (grunts, swarmers, hunters). Each bay destroyed stops its launches. The core only fires
when all bays are dead, and then it rams.
*Counterplay:* torpedoes into bays; prioritise over the core.

**6. CRAB MECH "PINCER"** (M) — body with two claws on arms. Claws slam down a column
(telegraphed red stripe), then sweep sideways. Destroy a claw and the arm whips loose as a
spinning hazard. Below 30% the body detaches its legs and they become 4 walking turrets.

**7. TWINS "CASTOR & POLLUX"** (S-M) — two ships joined by a laser tether you must not cross.
They circle each other, so the tether sweeps. Kill one and the other starts a 6 s revive
countdown; kill both inside the window or the dead one returns at 50%.
*Counterplay:* splitting fire, torpedo for the finish.

**8. FORTRESS STATION "ANVIL"** (L) — a stationary station seen from above with 6 pylons.
Pylons project a laser lattice that changes shape; each pylon destroyed removes its lines and
opens space. Core vents (weak) only during a 2 s cool-down after its big beam.

---

## C. Space monsters

**9. LEVIATHAN "THE DROWNED STAR"** (L) — so big only its head fits on screen; the body scrolls
past in the background. Its eye opens to fire and that is the only time it takes full damage.
Signature: INHALE (gravity pull toward the mouth for 2 s, debris flies in) then SPIT
(a wall of debris with one gap). Phase 2 it surfaces from the BOTTOM of the screen and
you fight it facing down.
*Counterplay:* beam the eye, survive the pull with the engine upgrade.

**10. KRAKEN "ABYSSAL BLOOM"** (M) — 6 tentacles as long line hazards that sweep slowly.
Tentacle tips are targets; sever a tip and that tentacle withers. The beak fires ink clouds
that dim part of the screen for 3 s (just darken, never full blind).

**11. JELLYFISH "MEDUSA VEIL"** (S, monster) — translucent bell trailing stinging tendrils
(contact damage strings). Pulses electric rings outward. Fades out like the SHADE enemy; only its
nucleus is solid while it glows. Calm, hypnotic fight, good as an act opener.

**12. BROOD QUEEN "SPAWNWELL"** (M) — body covered in 6 egg sacs that swell over 8 s and hatch
swarmers. Pop sacs before they hatch. Popped sacs leak acid puddles that drift down.
(Natural upgrade path for the existing HIVE MOTHER.)

**13. VOID MOTH "LUMEN"** (M) — huge wings reflect phaser shots back at you (reflector
primitive). Beam burns the wings off over time; then its body is fast and fragile.
Spore clouds drift down as slow bullets.
*Counterplay:* forces the beam.

**14. ROCK EATER "LITHOVORE"** (S-M) — a living asteroid with armor plates. Each plate you break
falls as an asteroid hazard (reuse asteroid code), revealing glowing magma underneath that takes
double damage. It eats asteroids to regrow plates.

**15. PARASITE "THE PASSENGER"** (M) — a worm that jumps between host ships: it latches onto a
normal enemy, making it an armored elite with boss patterns. Kill the host and it jumps to the
next one (or tries for your SIDEKICK: a grab telegraph you can dodge). After 4 hosts it fights
alone, naked and fast.

---

## D. Shapeshifters

**16. MIMIC "MIRROR PILOT"** (M) — copies your ship at boss scale. It mirrors your horizontal
movement (you go left, it goes right) and fires a giant copy of your CURRENT weapon:
phaser = bullet fan, beam = sweeping beam, missiles = homing salvo. Switching weapons on the
fire wheel switches its weapon too, so you choose which attack you face.
Phase 2: it copies the weapon you used most this run (we already track fire seconds per weapon).

**17. CHIMERA ENGINE** (L) — 4 forms at 100/75/50/25%:
FORTRESS (slow, heavy armor, bullet walls with a gap) -> BLADE (fast, dash charges across the
screen) -> SWARM (breaks into 12 drones that must all die or they reform in 6 s) -> SERPENT
(short worm). Each form has its own sprite. The morph is the spectacle.

**18. QUICKSILVER** (M) — liquid metal blob. Heavy hits split it: 1 -> 2 -> 4 droplets that share
one HP bar. Droplets drift back together and merge after 5 s, healing a little.
*Counterplay:* torpedo splits it on purpose so missiles can mop up the small ones.

**19. TESSERACT** (M) — a rotating 4D cube. One face at a time faces you; each face is weak to
ONE weapon (marked with that weapon's colour on the fire wheel) and immune to the others, and
each face has its own attack. Rotation every ~6 s, faster in later phases.
*Best fire-wheel fight in the game:* it teaches the wheel.

**20. PHANTOM PRISM** (S) — splits into 3-5 mirror images; only the real one has a shadow / a
faint outline. Hitting a decoy pops it into a burst of bullets. (Upgrade path for CRYSTAL PRISM.)

**21. SHIFTING GOD "NULL CHOIR"** (M) — fires two colours of bullets at once, but only one
colour is solid each phase (the other is a harmless ghost). The live colour flips every ~5 s,
shown on its hull and the HUD. Readable, unusual, very bullet-hell.

---

## E. Gimmick / arena bosses

**22. EVENT HORIZON** (M) — a black hole with 3 orbiting moon-turrets. Its gravity pulls the
ship slowly and bends YOUR bullets around it (curved shots). Shoot the moons to shrink the well;
the core is only reachable when the well is weak.

**23. SOLAR FORGE** (M) — a star-furnace whose corona flares sweep the screen; the only safe
spots are shadows cast by drifting debris. Short, intense.

**24. CHRONARCH** (L) — a time boss. "Echo": a ghost of your ship replays your last 3 s of
movement as a hazard. "Rewind": undoes the damage of the last 4 s unless you break its hourglass
part. Slow fields freeze bullets, then release them all at once.

**25. HACKER "GHOST SIGNAL"** (S) — emits glitch pulses that lock one wedge of the fire wheel
for 5 s (greyed out with static), forcing you to switch weapons. Never touches movement.

**26. THE CHASE "RUNNER"** (M) — the boss flees down the screen while scroll speed doubles and
asteroids rush past; drop its HP before the timer or it escapes and returns later in the act
stronger (a recurring rival!).

**27. PLANET CANNON "HELIOS LANCE"** (L) — the boss is a giant cannon in the background charging a
shot at a planet (story stakes). Destroy 4 capacitor drones that orbit it before the charge bar
fills; failure = huge screen-wide blast you must survive in a shielded pocket.

**28. FROM BELOW "UNDERTOW"** (S) — enters from the bottom of the screen behind you; you must
fly up into the enemy waves while it pushes. Short mid-sector ambush.

---

## F. Mini-bosses (for sectors without a boss)

Today only 7 of 24 sectors have a boss. Short 30-40 s mini-bosses mid-sector make the middle
of each act memorable:
- **ELITE GUNSHIP** — a big strafer with 2 breakable side guns.
- **TWIN LANCERS** — two lancers on a tether (small Castor & Pollux).
- **MINE MOTHER** — a minelayer the size of a boss, lays a field you must clear.
- **SHADE STALKER** — a big shade that only appears to fire.
- **BROOD POD** — egg sac cluster drifting down (small Spawnwell).
- **JELLY SWARM** — 3 small Medusas.

---

## G. Upgrades for the existing 8 bosses

| Boss | Today | Upgrade idea |
|---|---|---|
| HORNET QUEEN (s4) | drift + bursts | launches 2 hornet escorts, stinger dash in phase 3 |
| IRON TORTOISE (s8) | drift + shells | multi-part: shell plates + 4 leg turrets; shell off = soft body |
| HIVE MOTHER (s12) | radial + burst | egg sacs that hatch swarmers (Spawnwell rules) |
| CRYSTAL PRISM (s16) | radial + spiral | mirror decoys (Phantom Prism) + phaser reflection on one facet |
| VOID REAPER (s19) | spiral + fan | scythe sweep (rotating laser arm), cloaks like a shade between swings |
| NULL ARCHON (s22) | spiral + beam | shield ring of 4 nodes (Halo rules) |
| THE HERALD (s24) | fan + homing | mimic: copies your weapon (Mirror Pilot rules) |
| THE SKYBREAKER (s24) | radial + spiral | 3-stage multi-part finale: armor plates -> turrets -> exposed heart that shapeshifts |

---

## H. Recommended build order

1. **Framework**: BossPart + core shield rule + form script + `trail` and `dash` movement + bullet wall / rotating arm / minion launch primitives.
2. **IRON TORTOISE upgrade** (multi-part, proves BossPart on a known fight).
3. **VORM serpent** (new boss, the "space monster" headline).
4. **TESSERACT** (shapeshift + fire wheel teaching).
5. **MIMIC as the new Herald** (memorable story beat in the finale).
6. **SKYBREAKER 3-stage finale**.
7. Then monsters (Leviathan, Kraken, Spawnwell) and mini-bosses for non-boss sectors.

Art: one prompt per boss body plus per-part sprites (turret, segment, head, plate), generated
with the translate-skill art profiles and cut out with `scripts/tools/cutout_sprite.py`.
Tests: one headless test per boss (parts die in order, core shield rule, forms switch at
thresholds, no lane fully blocked).

---

## I. Status

- 10/11: framework built (`scripts/BossPart.gd`, `Boss.add_part / part_fire / core_shielded`,
  `hit_half` boxes in HitCheck, ram + missile rules cover `boss_parts`). IRON TORTOISE (s8) is
  multi-part: 3 shell plates (core takes 15% while any stands), 4 leg turrets, "SHELL CRACKED!"
  = armor 1 + faster + full-rate cannon. Tests: `BossPartsTest.tscn` (20), look check
  `BossShot.tscn` (windowed). Parts are drawn in code; real part art can replace them later.
- New bosses in sectors that have no boss today need the server's per-sector score ceiling
  (`skybreaker/api/lb.php`) raised first, or honest runs get flagged. Upgrading the existing
  boss sectors (4, 8, 12, 16, 19, 22, 24) needs no server change.

---

# Sidekick upgrade options

Today: one wingmate (hire at the shop or rare drop), 6 HP, 1 shield pip, wanders the bottom
quarter, picks a weapon different from yours, inherits your power level (cap 16), fires at
55% of your rate. Nothing to buy for it after hiring.

**Stat track (shop, carried + saved like the torpedo warhead):**
1. **WING ARMOR** 3 levels: hull 6 -> 9 -> 12 -> 16.
2. **WING SHIELD** 3 levels: shield pips 1 -> 2 -> 3, faster recharge.
3. **FIRE CONTROL** 3 levels: rate 55% -> 70% -> 85%, power cap 16 -> 22 -> 30.
4. **WEAPON LINK**: choose its weapon (P / B / M) or "MATCH" (same as yours) instead of random.

**Behaviour modes (free toggle in the shop or a long-press on the ship):**
5. **WINGMAN**: tight on your flank, mirrors your moves (focus fire).
6. **GUARD**: sits just ahead of you and soaks bullets aimed at you (spends its HP for yours).
7. **HUNTER**: roams the upper screen chasing targets; great on boss parts.
8. **ORBIT**: circles you; its shots spray in all directions.

**Ability unlocks (one-time buys, bigger price):**
9. **INTERCEPTOR**: shoots down homing missiles and mines that target you.
10. **WING TORPEDO**: fires its own torpedo every 20 s at the biggest target (boss part first).
11. **BEAM LINK**: when both of you fire beams, a tether between the ships burns whatever crosses it.
12. **LAST STAND**: once per sector it throws itself in front of a hit that would kill you.
13. **SALVAGE**: auto-collects money and pickups near it (a second magnet).
14. **FIELD REPAIR**: restores 1 hull pip on your ship every 20 s while it lives.
15. **EJECT POD**: when it dies a pilot pod drops; catch it and the next rehire is half price.

**Bigger ideas:**
16. **SECOND WING SLOT** (late game, expensive): two wingmates, one each side.
17. **VETERANCY**: kills rank it up Rookie -> Veteran -> Ace (+damage, + a name tag); lost on death, which makes you protect it.
18. **HULL CLASSES** to hire: STRIKER (damage), BULWARK (tank, shield wall), MEDIC (repairs you), SCOUT (magnet + marks targets for +10% damage).

Recommended first batch: WING ARMOR + WING SHIELD + WEAPON LINK (cheap, all in the existing
shop flow), then GUARD / HUNTER modes, then INTERCEPTOR and LAST STAND.
