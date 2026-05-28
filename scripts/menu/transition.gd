extends Node2D

static var premier_lancement = true

@onready var book_anim = $AnimatedSprite2D
@onready var anim_apparition = $apparition
@onready var anim_disparition = $disparition
@onready var anim_turn = $turn_left
@onready var menu_ui = $MenuContent
@onready var scroll_container = $ScrollContainer
@onready var menu_interactif = $MenuInteractif 

@onready var btn_solo = $"%Play Solo"
@onready var btn_multi = $"%Multi"
@onready var btn_profile = $"%Profile"
@onready var btn_maps = $"%Maps"
@onready var btn_settings = $"%Settings"

@onready var mark_solo = $MenuInteractif/Solo_vs_ia
@onready var mark_multi = $MenuInteractif/Multi
@onready var mark_profil = $MenuInteractif/Profil
@onready var mark_maps = $MenuInteractif/Maps
@onready var mark_settings = $MenuInteractif/Settings
@onready var mark_menu = $MenuInteractif/Menu 

@onready var btn_back_settings = get_node_or_null("Settings2/BackToMenu")
@onready var btn_back_profil = get_node_or_null("Profil2/BackToMenu")
@onready var btn_back_maps = get_node_or_null("Maps2/BackToMenu")
@onready var btn_back_solo = get_node_or_null("SoloVsIa/BackToMenu")
@onready var btn_back_multi = get_node_or_null("Multi2/PageGauche/BackToMenu") 

var current_active_menu: Node = null
var original_positions = {} 
var current_active_bookmark: TextureButton = null
const OFFSET_X = -12.0 
var is_transitioning: bool = false

func _ready():
	if premier_lancement:
		TranslationServer.set_locale("en")
		premier_lancement = false
	
	menu_ui.visible = false
	scroll_container.visible = false
	menu_interactif.visible = false 
	menu_interactif.modulate.a = 0  
	
	anim_apparition.hide()
	anim_disparition.hide()
	anim_turn.hide()
	
	_cacher_tous_les_sous_menus()
	_sauvegarder_positions_initiales()
	_connecter_signaux()
	
	book_anim.stop()
	book_anim.frame = 0
	
	await get_tree().create_timer(0.5).timeout 
	book_anim.play("Open_book")

func _on_animated_sprite_2d_animation_finished():
	if book_anim.animation == "Open_book":
		menu_ui.visible = true
		scroll_container.visible = true
		menu_interactif.visible = true
		
		_animer_marque_page(mark_menu)
		
		var tween = create_tween()
		menu_ui.modulate.a = 0
		scroll_container.modulate.a = 0
		tween.tween_property(menu_ui, "modulate:a", 1.0, 0.5)
		tween.parallel().tween_property(scroll_container, "modulate:a", 1.0, 0.5)
		tween.parallel().tween_property(menu_interactif, "modulate:a", 1.0, 0.5)

func _on_menu_principal_pressed() -> void:
	if current_active_menu == null and menu_ui.visible:
		return
	
	if is_transitioning: return
	
	_animer_marque_page(mark_menu)
	is_transitioning = true
	
	var tween_out = create_tween()
	if current_active_menu:
		tween_out.tween_property(current_active_menu, "modulate:a", 0.0, 0.2)
	await tween_out.finished
	
	if current_active_menu:
		current_active_menu.visible = false
		current_active_menu = null 
	
	menu_ui.visible = true
	scroll_container.visible = true
	menu_ui.modulate.a = 0
	scroll_container.modulate.a = 0
	
	var tween_in = create_tween()
	tween_in.tween_property(menu_ui, "modulate:a", 1.0, 0.3)
	tween_in.parallel().tween_property(scroll_container, "modulate:a", 1.0, 0.3)
	await tween_in.finished
	
	is_transitioning = false

func _animer_marque_page(nouveau_bouton: TextureButton) -> void:
	if current_active_bookmark == nouveau_bouton:
		return
		
	var tween = create_tween().set_parallel(true)
	
	if current_active_bookmark:
		var position_depart = original_positions[current_active_bookmark]
		tween.tween_property(current_active_bookmark, "position:x", position_depart, 0.2).set_trans(Tween.TRANS_SINE)
		
	current_active_bookmark = nouveau_bouton
	var position_sortie = original_positions[nouveau_bouton] + OFFSET_X
	tween.tween_property(nouveau_bouton, "position:x", position_sortie, 0.2).set_trans(Tween.TRANS_SINE)

func _on_solo_pressed() -> void:
	if is_transitioning: return 
	_animer_marque_page(mark_solo)
	_jouer_transition_complete($SoloVsIa)

func _on_multi_pressed() -> void:
	if is_transitioning: return 
	_animer_marque_page(mark_multi)
	_jouer_transition_complete($Multi2)

func _on_profile_pressed() -> void:
	if is_transitioning: return 
	_animer_marque_page(mark_profil)
	_jouer_transition_complete($Profil2)

func _on_maps_pressed() -> void:
	if is_transitioning: return 
	_animer_marque_page(mark_maps)
	_jouer_transition_complete($Maps2)

func _on_settings_pressed() -> void:
	if is_transitioning: return 
	_animer_marque_page(mark_settings)
	_jouer_transition_complete($Settings2)

func _jouer_transition_complete(target_menu: Node) -> void:
	if not target_menu:
		return
		
	if current_active_menu == target_menu:
		return

	is_transitioning = true

	var tween_out = create_tween()
	if current_active_menu:
		tween_out.tween_property(current_active_menu, "modulate:a", 0.0, 0.2)
	elif menu_ui.visible: 
		tween_out.tween_property(menu_ui, "modulate:a", 0.0, 0.2)
		tween_out.parallel().tween_property(scroll_container, "modulate:a", 0.0, 0.2)
	await tween_out.finished
	
	menu_ui.visible = false
	scroll_container.visible = false
	if current_active_menu:
		current_active_menu.visible = false

	anim_disparition.show()
	anim_disparition.play("disparition") 
	await anim_disparition.animation_finished
	anim_disparition.hide() 
	
	anim_turn.show()
	anim_turn.play("default") 
	await anim_turn.animation_finished
	anim_turn.hide()
	
	anim_apparition.show()
	anim_apparition.play("appear") 
	await anim_apparition.animation_finished
	anim_apparition.hide()
	
	target_menu.modulate.a = 0.0
	target_menu.visible = true
	current_active_menu = target_menu
	
	var tween_in = create_tween()
	tween_in.tween_property(target_menu, "modulate:a", 1.0, 0.4) 
	await tween_in.finished

	is_transitioning = false

func _connecter_signaux():
	btn_solo.pressed.connect(_on_solo_pressed)
	btn_multi.pressed.connect(_on_multi_pressed)
	btn_profile.pressed.connect(_on_profile_pressed)
	btn_maps.pressed.connect(_on_maps_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)

	mark_solo.pressed.connect(_on_solo_pressed)     
	mark_multi.pressed.connect(_on_multi_pressed)   
	mark_profil.pressed.connect(_on_profile_pressed) 
	mark_maps.pressed.connect(_on_maps_pressed)     
	mark_settings.pressed.connect(_on_settings_pressed)
	mark_menu.pressed.connect(_on_menu_principal_pressed)

	if btn_back_settings: btn_back_settings.pressed.connect(_on_menu_principal_pressed)
	if btn_back_profil:   btn_back_profil.pressed.connect(_on_menu_principal_pressed)
	if btn_back_maps:     btn_back_maps.pressed.connect(_on_menu_principal_pressed)
	if btn_back_solo:     btn_back_solo.pressed.connect(_on_menu_principal_pressed)
	if btn_back_multi:    btn_back_multi.pressed.connect(_on_menu_principal_pressed)

func _sauvegarder_positions_initiales():
	var marks = [mark_solo, mark_multi, mark_profil, mark_maps, mark_settings, mark_menu]
	for m in marks:
		if m: original_positions[m] = m.position.x

func _cacher_tous_les_sous_menus():
	var menus = ["SoloVsIa", "Multi2", "Profil2", "Maps2", "Settings2"]
	for m in menus:
		if has_node(m): get_node(m).visible = false
