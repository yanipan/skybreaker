extends Node
## Audio manager singleton.
## Handles SFX pooling, music crossfade, and haptic feedback.
##
## IMPORTANT: every audio asset is loaded LAZILY (on first access via the
## SFX_*() helper functions) instead of `preload()`'d at script-parse time.
##
## Why: this script is an autoload, so its constants are evaluated BEFORE
## the very first scene (Boot.tscn) gets to draw a single frame. Preloading
## ten MP3s here was costing the player 2-3 seconds of dark screen on every
## launch — Godot was sitting in the audio importer while nothing was on
## screen yet. Lazy loading drops the boot cost to ~0 ms; each clip pays
## its own decode the first time it actually plays, which is invisible.
##
## Other scripts call e.g. AudioManager.SFX_BEAM today as a property; we
## keep that exact spelling working by exposing each clip as a function
## call dressed up as the same name. Existing call sites stay untouched.

const SFX_POOL_SIZE: int = 16

# Asset paths — kept as constants so the file is the single source of
# truth, but the actual AudioStream resources are loaded on demand.
const _PATH_BG_MUSIC: String = "res://assets/audio/music/basic-bg-music.mp3"
## Story cutscenes (9/11): dark ambient loop made by
## scripts/tools/make_cutscene_music.py. Crossfaded in while the slides
## play, back to the game track when they end.
const _PATH_CUTSCENE_MUSIC: String = "res://assets/audio/music/cutscene_mystery.mp3"
## Narration clips live here as <beat image_file>.mp3 (scripts/tools/narration_tts.mjs).
const NARRATION_DIR: String = "res://assets/audio/narration/"
const _PATH_PLAYER_SHOT: String = "res://assets/audio/sfx/playershot1.mp3"
const _PATH_COIN_PICKUP: String = "res://assets/audio/sfx/coinpickup.mp3"
const _PATH_TORPEDO_FIRE: String = "res://assets/audio/sfx/torpedofire.mp3"
const _PATH_TORPEDO_EXPLOSION: String = "res://assets/audio/sfx/torpedoexplosion.mp3"
const _PATH_TAKING_IMPACT: String = "res://assets/audio/sfx/takingimpact.mp3"
const _PATH_SPACESHIP_EXPLODING: String = "res://assets/audio/sfx/spaceship_exploding.mp3"
const _PATH_POWERUP_ZAP: String = "res://assets/audio/sfx/electric_powerup_zap.mp3"
const _PATH_BEAM: String = "res://assets/audio/sfx/beamsound.mp3"
const _PATH_MISSILE_LAUNCH: String = "res://assets/audio/sfx/missilelaunch.mp3"
const _PATH_RED_ALERT: String = "res://assets/audio/sfx/red_alert.mp3"   ## scripts/tools/make_alert_sfx.py

# Cached AudioStreams keyed by path. First access populates the cache;
# every subsequent call is a dictionary hit.
var _stream_cache: Dictionary = {}

var BG_MUSIC: AudioStream:
	get:
		return _get_stream(_PATH_BG_MUSIC)
var CUTSCENE_MUSIC: AudioStream:
	get:
		return _get_stream(_PATH_CUTSCENE_MUSIC)

# These look like properties to call sites (AudioManager.SFX_BEAM) but are
# actually getters that route through the lazy cache. Drop-in compatible
# with the previous `const SFX_X = preload(...)` pattern — no other file
# needs to change.
var SFX_PLAYER_SHOT: AudioStream:
	get: return _get_stream(_PATH_PLAYER_SHOT)
var SFX_COIN_PICKUP: AudioStream:
	get: return _get_stream(_PATH_COIN_PICKUP)
var SFX_TORPEDO_FIRE: AudioStream:
	get: return _get_stream(_PATH_TORPEDO_FIRE)
var SFX_TORPEDO_EXPLOSION: AudioStream:
	get: return _get_stream(_PATH_TORPEDO_EXPLOSION)
var SFX_TAKING_IMPACT: AudioStream:
	get: return _get_stream(_PATH_TAKING_IMPACT)
var SFX_SPACESHIP_EXPLODING: AudioStream:
	get: return _get_stream(_PATH_SPACESHIP_EXPLODING)
var SFX_POWERUP_ZAP: AudioStream:
	get: return _get_stream(_PATH_POWERUP_ZAP)
var SFX_BEAM: AudioStream:
	get: return _get_stream(_PATH_BEAM)
var SFX_MISSILE_LAUNCH: AudioStream:
	get: return _get_stream(_PATH_MISSILE_LAUNCH)
var SFX_RED_ALERT: AudioStream:
	get: return _get_stream(_PATH_RED_ALERT)
## Drop a `shield_hit.mp3` into assets/audio/sfx and add a path constant +
## getter to enable a distinct shield-impact sound. Until then it falls back
## to a soft takingimpact play in Player._take_damage.
const SFX_SHIELD_HIT: AudioStream = null

var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
## Second music deck so a cutscene track can crossfade over the game track
## and hand back without a gap. `_music_player` is always the live deck.
var _music_player_alt: AudioStreamPlayer
## Narration deck: one line at a time, music ducks while it speaks.
var _voice_player: AudioStreamPlayer
var _cutscene_music_on: bool = false
var _sfx_index: int = 0
var _pending_music: bool = true   ## Music boot is deferred — see _ready


func _ready() -> void:
	# Music keeps playing under the pause screen and the (tree-paused)
	# story cutscenes, and narration must run while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Music players (two decks, see _music_player_alt)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	add_child(_music_player)
	_music_player_alt = AudioStreamPlayer.new()
	_music_player_alt.bus = &"Music"
	add_child(_music_player_alt)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = &"SFX"
	_voice_player.finished.connect(_on_voice_finished)
	add_child(_voice_player)

	# SFX pool
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_sfx_players.append(p)

	# Defer music boot to the next frame so the BG_MUSIC decode (which is
	# the heaviest single asset in the project) doesn't block the very
	# first paint of Boot.tscn. The player sees the loader instantly and
	# the music quietly fades in a frame later.
	call_deferred("_boot_music")


func _boot_music() -> void:
	if not _pending_music:
		return
	_pending_music = false
	var stream: AudioStream = BG_MUSIC
	if stream == null:
		return
	# AudioStreamMP3 has the loop property; cast safely.
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	play_music(stream)


## Lazy resource fetch. Hits the cache; first miss does the actual load.
func _get_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	var s: AudioStream = load(path) as AudioStream
	_stream_cache[path] = s
	return s


## Optional warm-up hook — Boot.gd can call this AFTER the loader has
## drawn its first frame to populate the cache in the background, so the
## first in-game shot doesn't pay a one-off decode hitch.
func warm_assets() -> void:
	for path in [
		_PATH_PLAYER_SHOT, _PATH_COIN_PICKUP, _PATH_TORPEDO_FIRE,
		_PATH_TORPEDO_EXPLOSION, _PATH_TAKING_IMPACT, _PATH_SPACESHIP_EXPLODING,
		_PATH_POWERUP_ZAP, _PATH_BEAM, _PATH_MISSILE_LAUNCH,
	]:
		if not _stream_cache.has(path):
			_stream_cache[path] = load(path)


func play_player_shot() -> void:
	play_sfx(SFX_PLAYER_SHOT, -6.0)


func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer = _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % SFX_POOL_SIZE
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch   # pooled players: always set, 1.0 unless asked
	player.play()


## Target playback volume for music once fully faded in
const MUSIC_TARGET_DB: float = -8.0
const MUSIC_SILENT_DB: float = -60.0

var _music_tween: Tween


func play_music(stream: AudioStream, fade_in: float = 2.0) -> void:
	if stream == null:
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_player.stream = stream
	_music_player.volume_db = MUSIC_SILENT_DB
	_music_player.play()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", MUSIC_TARGET_DB, fade_in)


func stop_music(fade_out: float = 1.0) -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", MUSIC_SILENT_DB, fade_out)
	_music_tween.tween_callback(_music_player.stop)


## Crossfade the live deck to `stream`: the old deck fades out on the alt
## player while the new one fades in. Both tweens run while the tree is
## paused (this node is PROCESS_MODE_ALWAYS).
func crossfade_music(stream: AudioStream, duration: float = 1.5) -> void:
	if stream == null:
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	var old: AudioStreamPlayer = _music_player
	var fresh: AudioStreamPlayer = _music_player_alt
	_music_player = fresh
	_music_player_alt = old
	fresh.stream = stream
	fresh.volume_db = MUSIC_SILENT_DB
	fresh.play()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	_music_tween.tween_property(fresh, "volume_db", _music_target_db(), duration)
	_music_tween.tween_property(old, "volume_db", MUSIC_SILENT_DB, duration)
	_music_tween.set_parallel(false)
	_music_tween.tween_callback(old.stop)


## Story slides: swap to the dark ambient loop.
func play_cutscene_music() -> void:
	if _cutscene_music_on:
		return
	var stream: AudioStream = CUTSCENE_MUSIC
	if stream == null:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_cutscene_music_on = true
	_pending_music = false
	crossfade_music(stream, 1.2)


## Slides over: back to the game track (no-op if the slides never swapped).
func end_cutscene_music() -> void:
	stop_voice()
	if not _cutscene_music_on:
		return
	_cutscene_music_on = false
	var stream: AudioStream = BG_MUSIC
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	crossfade_music(stream, 1.8)


## Ducking: music sits MUSIC_DUCK_DB lower while a narration line plays.
const MUSIC_DUCK_DB: float = -9.0
var _ducked: bool = false
var _duck_tween: Tween


func _music_target_db() -> float:
	return MUSIC_TARGET_DB + (MUSIC_DUCK_DB if _ducked else 0.0)


func _set_duck(on: bool) -> void:
	if _ducked == on:
		return
	_ducked = on
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	# Do not fight a running crossfade: it already targets _music_target_db().
	if _music_tween != null and _music_tween.is_valid() and _music_tween.is_running():
		return
	_duck_tween = create_tween()
	_duck_tween.tween_property(_music_player, "volume_db", _music_target_db(), 0.4)


## Play one narration line (stops the previous one). Returns the clip length
## in seconds, 0.0 when nothing played, so the caller can hold the slide.
func play_voice(stream: AudioStream, volume_db: float = 2.0) -> float:
	if stream == null:
		return 0.0
	_voice_player.stop()
	_voice_player.stream = stream
	_voice_player.volume_db = volume_db
	_voice_player.play()
	_set_duck(true)
	return stream.get_length()


func stop_voice() -> void:
	if _voice_player.playing:
		_voice_player.stop()
	_set_duck(false)


func _on_voice_finished() -> void:
	_set_duck(false)


## Narration clip for a cutscene beat, or null when none was generated.
func narration_for(image_file: String) -> AudioStream:
	var path: String = NARRATION_DIR + image_file + ".mp3"
	if not ResourceLoader.exists(path):
		return null
	return _get_stream(path)


func haptic_light() -> void:
	Input.vibrate_handheld(20)


func haptic_medium() -> void:
	Input.vibrate_handheld(50)


func haptic_heavy() -> void:
	Input.vibrate_handheld(100)
