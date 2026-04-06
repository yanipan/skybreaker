# Skybreaker — Game Design Document

**Status:** Draft v0.1 — Foundation
**Genre:** Vertical Scrolling Shoot-'em-Up (Shmup)
**Platforms:** iOS + Android (Portrait, Mobile-First)
**Engine:** Godot 4.3+ (GDScript)
**Inspiration:** Raptor: Call of the Shadows, Sky Force Reloaded, Tyrian

---

## 1. Vision Statement

Skybreaker is a modern mobile shoot-'em-up that captures the 90s arcade shooter thrill in bite-sized mobile sessions. Players fly through 5 themed sectors, destroying enemies, collecting money, and upgrading their ship in a satisfying hangar loop. Short missions (2-4 minutes), one-thumb controls, and deep progression make it easy to pick up and hard to put down.

## 2. Design Pillars

1. **Satisfying progression** — every mission rewards, every purchase matters
2. **Short sessions** — 2-4 minute missions for mobile moments
3. **One-handed playable** — thumb-only controls, no gymnastics
4. **Fair difficulty** — hard but never cheap; deaths feel earned
5. **Visual juice** — explosions, screen shake, feedback over everything

## 3. Core Loop

```
Hangar → Mission Select → Play Mission → Collect $ & Loot
   ↑                                              ↓
   └──── Buy Upgrades / Weapons / Ships ←─────────┘
```

## 4. Controls

| Action | Input |
|---|---|
| Move | Drag anywhere (ship offsets above finger) |
| Primary fire | Auto (always on) |
| Secondary weapon | Tap bottom-right button |
| Megabomb | Tap bomb icon or swipe up |
| Pause | Tap pause top-right |

## 5. Weapons

### Primary (swappable)
| Weapon | Niche | Tier 1 → Tier 5 |
|---|---|---|
| Vulcan Cannon | Reliable narrow | 100 → 250 DPS |
| Spread Shot | Crowd control | 80 → 200 DPS |
| Plasma Beam | Boss killer | 140 → 320 DPS |
| Homing Missiles | Lazy precision | 60 → 180 DPS |
| Rail Gun | Skill piercing | 120 → 400 burst |

### Secondary (limited ammo)
- Smart Bombs — clear nearby enemies
- EMP — stun all enemies for 3s
- Shield Burst — brief invulnerability + damage aura
- Drones — summon 2 auto-fire companions
- Nuke — massive single-target damage

## 6. Ships

| Ship | Role | Unlock Cost |
|---|---|---|
| Scout | Fast, fragile (starter) | Free |
| Striker | Balanced | $15,000 |
| Fortress | Tanky, heavy | $30,000 |
| Phantom | Crit/stealth | $45,000 |
| Titan | End-game, dual weapons | $50,000+ |

## 7. Upgrade Categories

- **Hull** — max HP
- **Shield** — regenerating buffer
- **Engine** — speed & agility
- **Cargo** — money multiplier
- **Magnet** — pickup radius

## 8. World Structure

| Sector | Theme | Missions | Boss |
|---|---|---|---|
| 1. Earth Orbit | Tutorial, blue skies | 8 | Orbital Defense Platform |
| 2. Lunar Defense | Moonscape, turrets | 10 | Lunar Command Fortress |
| 3. Asteroid Belt | Hazards, mining | 10 | Mining Leviathan |
| 4. Alien Frontier | Organic, weird | 10 | Hive Queen |
| 5. Mothership | Final gauntlet | 10 | Skybreaker (title boss) |

**Total: ~48 missions + 5 bosses**

## 9. Mission Structure (3 min avg)

```
0:00 → Start, light waves (tutorial enemies)
0:45 → First pressure wave
1:00 → Breather + pickups
1:30 → Mini-boss or elite
2:00 → Escalation, dense waves
2:30 → Boss intro (if end-sector) or final wave
3:00 → Mission complete → results screen
```

## 10. Economy

**Per-mission earnings:** Scale from $500 (Sector 1) to $4000 (Sector 5)

**Stars per mission** (Sky Force inspired):
- ⭐ Finish the mission
- ⭐ Destroy 70%+ of enemies
- ⭐ Take no damage
- ⭐ Rescue all civilians (Phase 2 feature)

## 11. Art Direction

- **Style:** Modern pixel art
- **Base resolution:** 1080x1920 portrait
- **Scaling:** Nearest-neighbor, pixel-perfect
- **Palette:** Master 32-color palette with sector-specific accents
- **Readability rule:** Player bullets cyan/white/yellow; enemy bullets red/magenta/orange — never mixed

## 12. Audio

- Upbeat electronic/synthwave soundtrack, one track per sector
- Punchy SFX library (shoot, hit, explode, pickup, UI)
- Haptic feedback on hits, explosions, and UI confirmations
- Music ducks during boss dialogue / intro

## 13. Monetization

**Model:** Free with rewarded ads + cosmetic IAP

- **Rewarded ads:** optional revive, 2x money, free secondary ammo refill
- **Cosmetic IAP:** alternate ship skins, trail effects, HUD themes
- **No pay-to-win.** All gameplay content unlockable through play.
- **No energy/stamina system.** Players can play as much as they want.

## 14. Accessibility

- Colorblind modes (Protanopia, Deuteranopia, Tritanopia)
- Haptics toggle
- Reduced motion mode
- Text scaling
- Hold-instead-of-tap option

## 15. Technical Specs

- **Engine:** Godot 4.3+
- **Language:** GDScript
- **Target FPS:** 60 locked
- **Min OS:** iOS 14, Android 8
- **Orientation:** Portrait lock
- **Save:** JSON at `user://savegame.dat`, versioned

## 16. Open Questions

- [ ] Will we have a story/narrative wrapper or purely arcade?
- [ ] Daily missions / events post-launch?
- [ ] Leaderboards (GameCenter / Google Play Games)?
- [ ] Cloud save?
- [ ] Offline-first vs online features?

---

*This document is living. Each agent will expand their relevant sections. The PM is the source of truth for scope. The Game Expert owns balance numbers. The Developer owns technical specs.*
