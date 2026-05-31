extends Node2D

static var first_launch: bool = true

@onready var book_anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var anim_appear: AnimatedSprite2D = $apparition
@onready var anim_disappear: AnimatedSprite2D = $disparition
@onready var anim_turn: AnimatedSprite2D = $turn_left
@onready var menu_ui: Control = $MenuContent
@onready var scroll_container: VBoxContainer = $ScrollContainer
@onready var interactive_menu: Control = $MenuInteractif

@onready var btn_solo: BaseButton = $"%Play Solo"
@onready var btn_multi: BaseButton = $"%Multi"
@onready var btn_profile: BaseButton = $"%Profile"
@onready var btn_maps: BaseButton = $"%Maps"
@onready var btn_settings: BaseButton = $"%Settings"

@onready var mark_solo: TextureButton = $MenuInteractif/Solo_vs_ia
@onready var mark_multi: TextureButton = $MenuInteractif/Multi
@onready var mark_profile: TextureButton = $MenuInteractif/Profil
@onready var mark_maps: TextureButton = $MenuInteractif/Maps
@onready var mark_settings: TextureButton = $MenuInteractif/Settings
@onready var mark_menu: TextureButton = $MenuInteractif/Menu
@onready var mark_unconnect: TextureButton = get_node_or_null("MenuInteractif/Unnconnect2")

@onready var btn_back_settings: BaseButton = get_node_or_null("Settings2/BackToMenu")
@onready var btn_back_profile: BaseButton = get_node_or_null("Profil2/BackToMenu")
@onready var unconnect_menu: Node = get_node_or_null("Unconnect2")
@onready var btn_back_maps: BaseButton = get_node_or_null("Maps2/BackToMenu")
@onready var btn_back_units: BaseButton = get_node_or_null("Units2/BackToMenu")
@onready var btn_back_solo: BaseButton = get_node_or_null("SoloVsIa/BackToMenu")
@onready var btn_back_multi: BaseButton = get_node_or_null("Multi2/PageGauche/BackToMenu")
@onready var multi_menu: Node = get_node_or_null("Multi2")

var current_active_menu: Node = null
var original_positions: Dictionary = {}
var current_active_bookmark: TextureButton = null
const OFFSET_X: float = -12.0
var is_transitioning: bool = false
var _profile_redirect_scheduled: bool = false
var _logout_redirect_scheduled: bool = false


func _ready() -> void:
	TranslationBootstrap.ensure_loaded()
	if first_launch:
		UserPrefs.set_language(UserPrefs.get_language(), false)
		first_launch = false
	if not UserPrefs.language_changed.is_connected(_on_language_changed):
		UserPrefs.language_changed.connect(_on_language_changed)

	menu_ui.visible = false
	scroll_container.visible = false
	interactive_menu.visible = false
	interactive_menu.modulate.a = 0

	anim_appear.hide()
	anim_disappear.hide()
	anim_turn.hide()

	_hide_all_submenus()
	_save_initial_bookmark_positions()
	_connect_signals()

	if Music.has_method("play_menu"):
		Music.play_menu()

	book_anim.stop()
	book_anim.frame = 0

	await get_tree().create_timer(0.5).timeout
	book_anim.play("Open_book")


func _on_language_changed(_locale: String) -> void:
	UserPrefs.apply_locale_now()


func _on_animated_sprite_2d_animation_finished() -> void:
	if book_anim.animation == "Open_book":
		Sound.play_menu3()
		menu_ui.visible = true
		scroll_container.visible = true
		interactive_menu.visible = true
		if UITranslator.has_method("refresh_tree"):
			UITranslator.refresh_tree()

		_animate_bookmark(mark_menu)

		var tween := create_tween()
		menu_ui.modulate.a = 0
		scroll_container.modulate.a = 0
		tween.tween_property(menu_ui, "modulate:a", 1.0, 0.5)
		tween.parallel().tween_property(scroll_container, "modulate:a", 1.0, 0.5)
		tween.parallel().tween_property(interactive_menu, "modulate:a", 1.0, 0.5)


func _on_main_menu_pressed() -> void:
	if current_active_menu == null and menu_ui.visible:
		return

	if is_transitioning:
		return

	Sound.play_menu2()
	_animate_bookmark(mark_menu)
	is_transitioning = true

	var tween_out := create_tween()
	if current_active_menu:
		tween_out.tween_property(current_active_menu, "modulate:a", 0.0, 0.2)
		await tween_out.finished
	else:
		tween_out.kill()

	if current_active_menu:
		current_active_menu.visible = false
		current_active_menu = null

	menu_ui.visible = true
	scroll_container.visible = true
	menu_ui.modulate.a = 0
	scroll_container.modulate.a = 0

	var tween_in := create_tween()
	tween_in.tween_property(menu_ui, "modulate:a", 1.0, 0.3)
	tween_in.parallel().tween_property(scroll_container, "modulate:a", 1.0, 0.3)
	await tween_in.finished

	is_transitioning = false


func _animate_bookmark(new_button: TextureButton) -> void:
	if current_active_bookmark == new_button:
		return

	Sound.play_menu1()
	var tween := create_tween().set_parallel(true)

	if current_active_bookmark:
		var start_position: float = original_positions[current_active_bookmark]
		tween.tween_property(current_active_bookmark, "position:x", start_position, 0.2).set_trans(Tween.TRANS_SINE)

	current_active_bookmark = new_button
	var extended_position: float = original_positions[new_button] + OFFSET_X
	tween.tween_property(new_button, "position:x", extended_position, 0.2).set_trans(Tween.TRANS_SINE)


func _on_solo_pressed() -> void:
	if is_transitioning:
		return
	_animate_bookmark(mark_solo)
	_play_full_transition($SoloVsIa)


func _on_play_solo_pressed() -> void:
	_on_solo_pressed()


func _on_solo_vs_ia_pressed() -> void:
	_on_solo_pressed()


func _on_multi_pressed() -> void:
	if is_transitioning:
		return
	_animate_bookmark(mark_multi)
	_play_full_transition($Multi2)


func _on_profile_pressed() -> void:
	if is_transitioning:
		return
	_animate_bookmark(mark_profile)
	_open_profile_or_unconnect()


func _on_unconnect_pressed() -> void:
	if is_transitioning:
		return
	if mark_unconnect != null:
		_animate_bookmark(mark_unconnect)
	else:
		_animate_bookmark(mark_profile)
	_open_profile_or_unconnect()


func _on_maps_pressed() -> void:
	if is_transitioning:
		return
	_animate_bookmark(mark_maps)
	_play_full_transition($Maps2)


func open_bestiary_maps() -> void:
	if is_transitioning:
		return
	_animate_bookmark(mark_maps)
	await _play_full_transition($Maps2)


func open_bestiary_unit(unit_index: int) -> void:
	if is_transitioning:
		return
	_animate_bookmark(mark_maps)
	await _play_full_transition($Units2)
	var units := get_node_or_null("Units2")
	if units != null and units.has_method("show_unit"):
		units.show_unit(unit_index)


func _on_settings_pressed() -> void:
	if is_transitioning:
		return
	_animate_bookmark(mark_settings)
	_play_full_transition($Settings2)


func _open_profile_or_unconnect() -> void:
	if NetworkSession.is_account_logged_in():
		_play_full_transition($Profil2)
	else:
		_play_full_transition($Unconnect2)


func _on_unconnect_auth_completed() -> void:
	if is_transitioning or _profile_redirect_scheduled:
		return
	if not NetworkSession.is_account_logged_in():
		return
	_profile_redirect_scheduled = true
	_animate_bookmark(mark_profile)
	await _play_full_transition($Profil2)
	_profile_redirect_scheduled = false


func _on_network_account_ready() -> void:
	if not NetworkSession.is_account_logged_in():
		return
	if current_active_menu == null or current_active_menu.name != "Unconnect2":
		return
	call_deferred("_on_unconnect_auth_completed")


func _on_logout_redirect_unconnect() -> void:
	if _logout_redirect_scheduled or is_transitioning:
		return
	if current_active_menu != null and current_active_menu.name == "Unconnect2":
		return
	_logout_redirect_scheduled = true
	call_deferred("_run_logout_to_unconnect")


func _run_logout_to_unconnect() -> void:
	if mark_unconnect != null:
		_animate_bookmark(mark_unconnect)
	else:
		_animate_bookmark(mark_profile)
	await _play_full_transition($Unconnect2)
	_logout_redirect_scheduled = false


func _play_full_transition(target_menu: Node) -> void:
	if not target_menu:
		return

	if current_active_menu == target_menu:
		return

	Sound.play_menu2()
	is_transitioning = true

	var tween_out := create_tween()
	var has_out_anim := false
	if current_active_menu:
		tween_out.tween_property(current_active_menu, "modulate:a", 0.0, 0.2)
		has_out_anim = true
	elif menu_ui.visible:
		tween_out.tween_property(menu_ui, "modulate:a", 0.0, 0.2)
		tween_out.parallel().tween_property(scroll_container, "modulate:a", 0.0, 0.2)
		has_out_anim = true
	if has_out_anim:
		await tween_out.finished
	else:
		tween_out.kill()

	menu_ui.visible = false
	scroll_container.visible = false
	if current_active_menu:
		current_active_menu.visible = false

	anim_disappear.show()
	anim_disappear.play("disparition")
	await anim_disappear.animation_finished
	anim_disappear.hide()

	anim_turn.show()
	anim_turn.play("default")
	await anim_turn.animation_finished
	anim_turn.hide()

	anim_appear.show()
	anim_appear.play("appear")
	await anim_appear.animation_finished
	anim_appear.hide()

	target_menu.modulate.a = 0.0
	target_menu.visible = true
	current_active_menu = target_menu

	var tween_in := create_tween()
	tween_in.tween_property(target_menu, "modulate:a", 1.0, 0.4)
	await tween_in.finished

	is_transitioning = false


func _connect_signals() -> void:
	btn_solo.pressed.connect(_on_solo_pressed)
	btn_multi.pressed.connect(_on_multi_pressed)
	btn_profile.pressed.connect(_on_profile_pressed)
	btn_maps.pressed.connect(_on_maps_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)

	mark_solo.pressed.connect(_on_solo_pressed)
	mark_multi.pressed.connect(_on_multi_pressed)
	mark_profile.pressed.connect(_on_profile_pressed)
	mark_maps.pressed.connect(_on_maps_pressed)
	mark_settings.pressed.connect(_on_settings_pressed)
	mark_menu.pressed.connect(_on_main_menu_pressed)
	if mark_unconnect != null:
		mark_unconnect.pressed.connect(_on_unconnect_pressed)

	if btn_back_settings:
		btn_back_settings.pressed.connect(_on_main_menu_pressed)
	if btn_back_profile:
		btn_back_profile.pressed.connect(_on_main_menu_pressed)
	if btn_back_maps:
		btn_back_maps.pressed.connect(_on_main_menu_pressed)
	if btn_back_units:
		btn_back_units.pressed.connect(_on_main_menu_pressed)
	if btn_back_solo:
		btn_back_solo.pressed.connect(_on_main_menu_pressed)
	if btn_back_multi:
		btn_back_multi.pressed.connect(_on_main_menu_pressed)
	if unconnect_menu != null and unconnect_menu.has_signal("auth_completed"):
		unconnect_menu.auth_completed.connect(_on_unconnect_auth_completed)
	if not NetworkSession.auth_ready.is_connected(_on_network_account_ready):
		NetworkSession.auth_ready.connect(_on_network_account_ready)
	if not NetworkSession.session_closed.is_connected(_on_logout_redirect_unconnect):
		NetworkSession.session_closed.connect(_on_logout_redirect_unconnect)
	if multi_menu != null and multi_menu.has_signal("requires_login"):
		multi_menu.requires_login.connect(_on_multi_requires_login)


func _save_initial_bookmark_positions() -> void:
	var marks: Array = [mark_solo, mark_multi, mark_profile, mark_maps, mark_settings, mark_menu, mark_unconnect]
	for m in marks:
		if m:
			original_positions[m] = m.position.x


func _hide_all_submenus() -> void:
	var menus: Array[String] = ["SoloVsIa", "Multi2", "Profil2", "Unconnect2", "Maps2", "Units2", "Settings2"]
	for m in menus:
		if has_node(m):
			get_node(m).visible = false


func _on_multi_requires_login() -> void:
	if is_transitioning:
		return
	if NetworkSession.is_account_logged_in():
		return
	if current_active_menu != null and current_active_menu.name == "Unconnect2":
		return
	if mark_unconnect != null:
		_animate_bookmark(mark_unconnect)
	else:
		_animate_bookmark(mark_profile)
	_play_full_transition($Unconnect2)
