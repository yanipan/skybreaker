extends Node
## Audio manager singleton.
## Handles SFX pooling, music crossfade, and haptic feedback.

const SFX_POOL_SIZE: int = 16

var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _sfx_index: int = 0


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


func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer = _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % SFX_POOL_SIZE
	player.stream = stream
	player.volume_db = volume_db
	player.play()


func play_music(stream: AudioStream, fade_in: float = 1.0) -> void:
	if stream == null:
		return
	_music_player.stream = stream
	_music_player.play()
	# TODO: implement fade-in via Tween


func stop_music(fade_out: float = 1.0) -> void:
	# TODO: implement fade-out
	_music_player.stop()


func haptic_light() -> void:
	Input.vibrate_handheld(20)


func haptic_medium() -> void:
	Input.vibrate_handheld(50)


func haptic_heavy() -> void:
	Input.vibrate_handheld(100)
