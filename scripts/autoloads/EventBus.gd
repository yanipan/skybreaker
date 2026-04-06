extends Node
## Global event bus for loose coupling between systems.
## Emit signals here instead of coupling unrelated nodes.

# --- Player signals ---
signal player_spawned(player: Node)
signal player_died
signal player_damaged(amount: int)
signal player_healed(amount: int)

# --- HUD signals ---
signal money_changed(new_total: int)
signal score_changed(new_total: int)
signal health_changed(current: int, max_hp: int)

# --- Mission signals ---
signal mission_started
signal mission_completed(success: bool)
signal boss_spawned(boss: Node)
signal boss_defeated

# --- Pickup signals ---
signal pickup_collected(type: StringName, value: int)

# --- UI signals ---
signal pause_requested
signal resume_requested
