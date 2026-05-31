extends Node2D

@onready var _music_slider: HSlider = $Music/MusicSlider
@onready var _sfx_slider: HSlider = $Music/SFXSlider


func _ready() -> void:
	_setup_volume_slider(_music_slider, UserPrefs.get_music_volume_percent())
	_setup_volume_slider(_sfx_slider, UserPrefs.get_sfx_volume_percent())
	_music_slider.value_changed.connect(_on_music_slider_value_changed)
	_sfx_slider.value_changed.connect(_on_sfx_slider_value_changed)


func _setup_volume_slider(slider: HSlider, percent: int) -> void:
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = float(percent)


func _on_music_slider_value_changed(value: float) -> void:
	UserPrefs.set_music_volume_percent(int(round(value)))


func _on_sfx_slider_value_changed(value: float) -> void:
	UserPrefs.set_sfx_volume_percent(int(round(value)))


func _on_option_button_item_selected(index: int) -> void:
	match index:
		0:
			UserPrefs.set_language("en")
		1:
			UserPrefs.set_language("fr")
		2:
			UserPrefs.set_language("de")
