# Skybreaker

A modern mobile vertical shoot-'em-up, built in Godot 4. Inspired by Raptor: Call of the Shadows.

## Stack
- **Engine:** Godot 4.3+
- **Language:** GDScript
- **Platforms:** iOS, Android (portrait, 60fps)
- **Art:** Modern pixel art
- **Monetization:** Free with rewarded ads + cosmetic IAP

## Project Structure

```
Skybreaker/
├── .claude/agents/        # Specialized AI agents
├── scenes/                # Godot scenes (.tscn)
│   ├── player/
│   ├── enemies/
│   ├── bullets/
│   ├── levels/
│   ├── ui/
│   └── main/
├── scripts/               # GDScript files
│   ├── autoloads/         # Singletons
│   ├── systems/           # Reusable systems
│   └── utils/             # Helpers
├── assets/
│   ├── sprites/
│   ├── audio/
│   └── fonts/
├── ui/                    # UI scenes and themes
├── docs/                  # Technical & design docs
├── GAME_DESIGN_DOC.md     # Full game design
├── ROADMAP.md             # Phase plan
└── TASKS.md               # Active task list
```

## Getting Started

1. Install [Godot 4.3+](https://godotengine.org/download)
2. Open Godot, click "Import"
3. Select `project.godot` in this folder
4. Hit Play

## The Team (AI Agents)

Specialized subagents in `.claude/agents/`:

- **skybreaker-pm** — Project manager, roadmap, task tracking
- **skybreaker-dev** — Godot/GDScript developer
- **skybreaker-art** — Pixel art direction, asset sourcing
- **skybreaker-ux** — Mobile UX, HUD, menu design
- **skybreaker-design** — Game balance, waves, bosses, juice

Invoke an agent via the Agent tool when you need their expertise.

## Documentation

- [`GAME_DESIGN_DOC.md`](./GAME_DESIGN_DOC.md) — Full vision and specs
- [`ROADMAP.md`](./ROADMAP.md) — Phase plan from MVP to launch
- [`TASKS.md`](./TASKS.md) — Current sprint tasks

## License

TBD
