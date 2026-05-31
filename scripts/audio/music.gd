extends Node

## Looping background music per map (files under assets/sounds/musique/).

const TRACKS_BY_MAP: Dictionary = {
	1: "res://assets/sounds/musique/map1.mp3",
	2: "res://assets/sounds/musique/map2.mp3",
	3: "res://assets/sounds/musique/map.mp3",
}

const DEFAULT_VOLUME_DB := -6.0

@onready var _player: AudioStreamPlayer = $MusicPlayer

var _current_map_index: int = -1


func _ready() -> void:
	if _player != null:
		_player.bus = &"Master"
		_player.volume_db = DEFAULT_VOLUME_DB


func play_for_map(map_index: int = -1) -> void:
	var idx: int = map_index if map_index > 0 else MapSession.active_map_index
	if idx == _current_map_index and _player != null and _player.playing:
		return

	var path: String = str(TRACKS_BY_MAP.get(idx, TRACKS_BY_MAP.get(1, "")))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("Music: no track for map index %s" % idx)
		return

	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		push_warning("Music: failed to load %s" % path)
		return

	_prepare_loop(stream)
	_current_map_index = idx
	if _player == null:
		return
	_player.stream = stream
	_player.play()


func stop() -> void:
	_current_map_index = -1
	if _player != null:
		_player.stop()


func set_volume_linear(linear_0_to_1: float) -> void:
	if _player == null:
		return
	var clamped := clampf(linear_0_to_1, 0.0, 1.0)
	_player.volume_db = -80.0 if clamped <= 0.0001 else linear_to_db(clamped) + DEFAULT_VOLUME_DB


func _prepare_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
