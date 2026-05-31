extends Node

## Looping background music — menu + one track per map (assets/sounds/musique/).

const MENU_TRACK := "res://assets/sounds/musique/menu.mp3"
const MENU_TRACK_ID := 0

const TRACKS_BY_MAP: Dictionary = {
	1: "res://assets/sounds/musique/map1.mp3",
	2: "res://assets/sounds/musique/map2.mp3",
	3: "res://assets/sounds/musique/map.mp3",
}

const DEFAULT_VOLUME_DB := -6.0

@onready var _player: AudioStreamPlayer = $MusicPlayer

var _current_track_id: int = -1
var _volume_linear: float = 0.5


func _ready() -> void:
	if _player != null:
		_player.bus = &"Master"
	call_deferred("_sync_user_volume")


func _sync_user_volume() -> void:
	if UserPrefs.has_method("get_music_linear"):
		set_volume_linear(UserPrefs.get_music_linear())


func play_menu() -> void:
	_play_track(MENU_TRACK, MENU_TRACK_ID)


func play_for_map(map_index: int = -1) -> void:
	var idx: int = map_index if map_index > 0 else MapSession.active_map_index
	var path: String = str(TRACKS_BY_MAP.get(idx, TRACKS_BY_MAP.get(1, "")))
	if path.is_empty():
		push_warning("Music: no track for map index %s" % idx)
		return
	_play_track(path, idx)


func stop() -> void:
	_current_track_id = -1
	if _player != null:
		_player.stop()


func set_volume_linear(linear_0_to_1: float) -> void:
	_volume_linear = clampf(linear_0_to_1, 0.0, 1.0)
	if _player == null:
		return
	_player.volume_db = -80.0 if _volume_linear <= 0.0001 else linear_to_db(_volume_linear) + DEFAULT_VOLUME_DB


func _play_track(path: String, track_id: int) -> void:
	if track_id == _current_track_id and _player != null and _player.playing:
		return
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("Music: track missing: %s" % path)
		return

	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		push_warning("Music: failed to load %s" % path)
		return

	_prepare_loop(stream)
	_current_track_id = track_id
	if _player == null:
		return
	_player.stream = stream
	_player.play()


func _prepare_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
