extends RefCounted
class_name CoopSession
## Small shared pieces of starting a co-op run (lobby screens and the dev launcher).

## Reset the run fields for a FRESH co-op run. Call only AFTER Net.start_coop():
## that is what freezes the solo run, money and lives so they can be put back.
static func begin_run(start_sector: int) -> void:
	GameState.begin_run(randi_range(1, 2147483646))
	GameState.lives = GameState.STARTING_LIVES
	GameState.current_level = maxi(1, start_sector)
	GameState.clear_carry()
	GameState.clear_respawn()
	GameState.reset_mission_stats()
	GameState.intro_seen = true
	GameState.resume_pending = false
	GameState.pending_warp_entry = false
	GameState.pending_story_key = &""
	GameState.has_active_run = true
	GameState.last_run = {}


## The name partners see. The leaderboard pilot name when there is one.
static func pilot_name() -> String:
	var n: String = str(Online.pilot_name).strip_edges()
	return n if n != "" else "PILOT"
