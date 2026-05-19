extends Node
## Static data table for the story cutscenes.
##
## This is a plain Node (not an autoload) used as a const container — the
## table is accessed directly via `CutsceneData.INTRO`, `CutsceneData.ACT_1`,
## etc. from Cutscene.gd and Main.gd. No instance state, no _ready logic.
##
## Trigger convention:
##   * INTRO plays ONCE on first-ever entry to sector 1, gated by
##     GameState.intro_seen. Triggered in Main._ready.
##   * ACT_1..ACT_4 play immediately after the player completes sectors
##     5, 10, 15, 19 — intercepted inside Main._check_level_complete
##     before the warp transition starts.
##   * ENDING plays after the player completes sector 20, the final
##     sector. After ending, the run state is wiped and the player is
##     bounced back to StartScreen.
##
## Caption copy is the draft approved in Track B (see
## assets/cutscenes/mockups/). Edit here to change dialog — the playback
## code reads these lists with no string literals of its own.

class_name CutsceneData

## One beat of a cutscene. `image_file` is the filename (no `.png`
## extension) inside `res://assets/cutscenes/`. If a matching `.mp4`
## exists at the same path, Cutscene.gd plays the video instead; it
## falls back to the still. `caption` is the line shown under the
## gradient panel. `duration` is how long the beat stays on screen
## before auto-advancing (the player can tap early to skip).
class Beat:
	var image_file: String
	var caption: String
	var duration: float
	func _init(img: String, cap: String, dur: float = 5.0) -> void:
		image_file = img
		caption = cap
		duration = dur


static func _beat(img: String, cap: String, dur: float = 5.0) -> Dictionary:
	return {"image_file": img, "caption": cap, "duration": dur}


## Intro — cold open, plays before sector 1 on first launch.
const INTRO_KEY: StringName = &"intro"
## Plays after player completes sector 5 (the sector transition that
## would have taken them from 5 → 6 instead plays this cutscene first).
const ACT_1_KEY: StringName = &"act1"
const ACT_2_KEY: StringName = &"act2"
const ACT_3_KEY: StringName = &"act3"
const ACT_4_KEY: StringName = &"act4"
## Plays after player completes sector 20, the final sector.
const ENDING_KEY: StringName = &"ending"

## Map of "which sector completion triggers which cutscene key" — read
## by Main._check_level_complete.
const TRIGGERS: Dictionary = {
	5: ACT_1_KEY,
	10: ACT_2_KEY,
	15: ACT_3_KEY,
	19: ACT_4_KEY,
	20: ENDING_KEY,
}


## Returns the beat list for a given cutscene key, or an empty array if
## unknown. Each beat is a Dictionary with image_file / caption / duration
## keys (see _beat helper above). Arrays are constructed per-call to keep
## the data co-located with the doc comments — cost is negligible, these
## play at most once per sector transition.
static func beats_for(key: StringName) -> Array:
	match key:
		INTRO_KEY:
			return [
				_beat("cutscene_00_intro_01_relay_station", "Earth orbit. 03:47 UTC.\nA signal from a dead colony."),
				_beat("cutscene_00_intro_02_signal_console", "Forty years of silence.\nAnd one word, repeating."),
				_beat("cutscene_00_intro_03_decoded_sigil", "SKYBREAKER.", 4.0),
				_beat("cutscene_00_intro_04_launch", "You're the only pilot close enough.\nLaunch."),
			]
		ACT_1_KEY:
			return [
				_beat("cutscene_01_act1_01_pirate_dogfight", "The pirates aren't attacking.\nThey're running."),
				_beat("cutscene_01_act1_02_dying_pilot", "One pilot transmits a final word\nbefore her ship cracks apart:"),
				_beat("cutscene_01_act1_03_drifting_wreckage", "It's awake.", 4.0),
			]
		ACT_2_KEY:
			return [
				_beat("cutscene_02_act2_01_dead_colony", "The colony isn't dead.\nIt's been waiting."),
				_beat("cutscene_02_act2_02_docking_tunnel", "The air smells wrong.\nThe walls aren't metal anymore."),
				_beat("cutscene_02_act2_03_rewritten_survivors", "They were human, once.\nSomething rewrote them."),
			]
		ACT_3_KEY:
			return [
				_beat("cutscene_03_act3_01_hive_artifact", "The swarm wasn't attacking you.\nIt was guarding."),
				_beat("cutscene_03_act3_02_bugs_falling", "The firewall is falling.\nYou helped it fall."),
				_beat("cutscene_03_act3_03_skybreaker_awake", "The weapon was buried for a reason.", 5.5),
			]
		ACT_4_KEY:
			return [
				_beat("cutscene_04_act4_01_heart_chamber", "Inside the heart.\nAncient. Listening."),
				_beat("cutscene_04_act4_02_grandmother_hologram", "It knows your name.\nIt was built from hers.", 6.0),
				_beat("cutscene_04_act4_03_chamber_waking", "\"If you're reading this, kill it.\nI'm sorry.\"", 6.0),
			]
		ENDING_KEY:
			return [
				_beat("cutscene_05_ending_01_skybreaker_falling", "It falls.\nThe stars go quiet."),
				_beat("cutscene_05_ending_02_homeward", "You turn for home.\nThe signal is gone."),
				_beat("cutscene_05_ending_03_new_signal", "And then, from deeper out...", 6.0),
			]
		_:
			return []
