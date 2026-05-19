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
const _PATH_PLAYER_SHOT: String = "res://assets/audio/sfx/playershot1.mp3"
const _PATH_COIN_PICKUP: String = "res://assets/audio/sfx/coinpickup.mp3"
const _PATH_TORPEDO_FIRE: String = "res://assets/audio/sfx/torpedofire.mp3"
const _PATH_TORPEDO_EXPLOSION: String = "res://assets/audio/sfx/torpedoexplosion.mp3"
const _PATH_TAKING_IMPACT: String = "res://assets/audio/sfx/takingimpact.mp3"
const _PATH_SPACESHIP_EXPLODING: String = "res://assets/audio/sfx/spaceship_exploding.mp3"
const _PATH_POWERUP_ZAP: String = "res://assets/audio/sfx/electric_powerup_zap.mp3"
const _PATH_BEAM: String = "res://assets/audio/sfx/beamsound.mp3"
const _PATH_MISSILE_LAUNCH: String = "res://assets/audio/sfx/missilelaunch.mp3"

# Cached AudioStreams keyed by path. First access populates the cache;
# every subsequent call is a dictionary hit.
var _stream_cache: Dictionary = {}

var BG_MUSIC: AudioStream:
	get:
		return _get_stream(_PATH_BG_MUSIC)

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
## Drop a `shield_hit.mp3` into assets/audio/sfx and add a path constant +
## getter to enable a distinct shield-impact sound. Until then it falls back
## to a soft takingimpact play in Player._take_damage.
const SFX_SHIELD_HIT: AudioStream = null

var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _sfx_index: int = 0
var _pending_music: bool = true   ## Music boot is deferred — see _ready


func _ready() -> void:
	# Music player
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	add_child(_music_player)

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


func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer = _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % SFX_POOL_SIZE
	player.stream = stream
	player.volume_db = volume_db
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


func haptic_light() -> void:
	Input.vibrate_handheld(20)


func haptic_medium() -> void:
	Input.vibrate_handheld(50)


func haptic_heavy() -> void:
	Input.vibrate_handheld(100)
