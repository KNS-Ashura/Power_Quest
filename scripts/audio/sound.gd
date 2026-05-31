extends Node

## Global SFX (non-positional). Use AudioStreamPlayer, not 2D — autoload is outside the game world.

const DEFAULT_VOLUME_DB := 0.0

@onready var menu_1: AudioStreamPlayer = $Menu1
@onready var menu_2: AudioStreamPlayer = $Menu2
@onready var menu_3: AudioStreamPlayer = $Menu3

@onready var heal: AudioStreamPlayer = $heal
@onready var boost: AudioStreamPlayer = $boost
@onready var nuclear: AudioStreamPlayer = $nuclear
@onready var antiarmor: AudioStreamPlayer = $antiarmor
@onready var transporter: AudioStreamPlayer = $transporter
@onready var upgrade: AudioStreamPlayer = $upgrade
@onready var capture: AudioStreamPlayer = $capture


var _sfx_volume_linear: float = 0.5


func _ready() -> void:
	_apply_volume_to_all()
	call_deferred("_sync_user_volume")


func _sync_user_volume() -> void:
	if UserPrefs.has_method("get_sfx_linear"):
		set_sfx_volume_linear(UserPrefs.get_sfx_linear())


func set_sfx_volume_linear(linear_0_to_1: float) -> void:
	_sfx_volume_linear = clampf(linear_0_to_1, 0.0, 1.0)
	var db := -80.0 if _sfx_volume_linear <= 0.0001 else linear_to_db(_sfx_volume_linear)
	for child in get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).volume_db = db


func set_master_volume_linear(linear_0_to_1: float) -> void:
	set_sfx_volume_linear(linear_0_to_1)


func _apply_volume_to_all() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			var player := child as AudioStreamPlayer
			player.volume_db = DEFAULT_VOLUME_DB
			player.bus = &"Master"


func _play(player: AudioStreamPlayer) -> void:
	if player == null or player.stream == null:
		push_warning("Sound: missing player or stream.")
		return
	if not player.playing:
		player.play()
	else:
		player.stop()
		player.play()


func play_menu1() -> void:
	_play(menu_1)


func play_menu2() -> void:
	_play(menu_2)


func play_menu3() -> void:
	_play(menu_3)


func play_heal() -> void:
	_play(heal)


func play_boost() -> void:
	_play(boost)


func play_nuclear() -> void:
	_play(nuclear)


func play_antiarmor() -> void:
	_play(antiarmor)


func play_transport() -> void:
	_play(transporter)


func play_upgrade() -> void:
	_play(upgrade)


func play_capture() -> void:
	_play(capture)
