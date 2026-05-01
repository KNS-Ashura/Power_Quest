extends Node2D

@onready var boite_selection = $BoiteSelection
@onready var camera = $Camera2D

var en_selection : bool = false
var point_depart : Vector2 = Vector2.ZERO
var batiment_selectionne : Node2D = null

signal batiment_selectionne_change(batiment)

@export var vitesse_camera : float = 400.0
@export var vitesse_zoom : float = 0.1
var zoom_cible : float = 1.0
var zoom_min : float = 0.5
var zoom_max : float = 2.0

func _ready():
	boite_selection.hide()
	add_to_group("manager_rts")
	if camera: camera.make_current()

func _process(delta):
	_gerer_mouvement_camera(delta)
	_gerer_zoom_camera(delta)

func _gerer_mouvement_camera(delta):
	var dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	
	if dir != Vector2.ZERO:
		camera.global_position += dir.normalized() * vitesse_camera * delta * (1.0 / camera.zoom.x)

func _gerer_zoom_camera(delta):
	camera.zoom = camera.zoom.lerp(Vector2(zoom_cible, zoom_cible), 10.0 * delta)

func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			en_selection = true
			point_depart = get_global_mouse_position()
			boite_selection.global_position = point_depart
			boite_selection.size = Vector2.ZERO
			boite_selection.show()
		else:
			en_selection = false
			boite_selection.hide()
			selectionner_unites()
			if boite_selection.size.length() < 5:
				_gerer_clic_batiment()

	if event is InputEventKey and event.keycode == KEY_E and event.pressed:
		var sort_lance = false
		for soldat in get_tree().get_nodes_in_group("soldats"):
			if soldat.get("est_selectionne") and soldat.has_method("lancer_sort"):
				soldat.lancer_sort()
				sort_lance = true
		if sort_lance: return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_cible = clamp(zoom_cible + vitesse_zoom, zoom_min, zoom_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_cible = clamp(zoom_cible - vitesse_zoom, zoom_min, zoom_max)

	if event is InputEventMouseMotion and en_selection:
		var pos = get_global_mouse_position()
		boite_selection.global_position = Vector2(min(point_depart.x, pos.x), min(point_depart.y, pos.y))
		boite_selection.size = Vector2(abs(pos.x - point_depart.x), abs(pos.y - point_depart.y))
		if boite_selection.size.length() > 10:
			deselect_batiment()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var dest = get_global_mouse_position()
		var selection = get_tree().get_nodes_in_group("soldats").filter(func(s): return s.get("est_selectionne"))
		var nb = selection.size()
		if nb == 0: return
		
		var requete = PhysicsPointQueryParameters2D.new()
		requete.position = dest
		requete.collide_with_areas = false
		requete.collide_with_bodies = true
		
		var resultats = get_world_2d().direct_space_state.intersect_point(requete)
		var cible = null
		
		for res in resultats:
			var obj = res.collider
			if obj and obj.has_method("recevoir_degats") and not obj.is_in_group("camps"):
				var eq = obj.get("equipe")
				if eq != null and eq != ServerConnection.local_side:
					cible = obj
					break
				
		if cible:
			for soldat in selection:
				if soldat.has_method("attaquer_cible"): soldat.attaquer_cible(cible)
		else:
			var cols = ceil(sqrt(nb))
			var espace = 24.0
			for i in range(nb):
				var offset = Vector2(
					(i % int(cols)) * espace - (cols - 1) * espace / 2.0,
					(float(i) / int(cols)) * espace - (ceil(float(nb) / cols) - 1) * espace / 2.0
				)
				selection[i].aller_vers(dest + offset)

func selectionner_unites():
	var zone = Rect2(boite_selection.global_position, boite_selection.size)
	for soldat in get_tree().get_nodes_in_group("soldats"):
		if soldat.has_method("set_selection"):
			soldat.set_selection(soldat.get("equipe") == ServerConnection.local_side and zone.has_point(soldat.global_position))

func _gerer_clic_batiment():
	var requete = PhysicsPointQueryParameters2D.new()
	requete.position = boite_selection.global_position
	requete.collide_with_areas = false
	requete.collide_with_bodies = true
	var resultats = get_world_2d().direct_space_state.intersect_point(requete)
	
	for res in resultats:
		if res.collider and res.collider.is_in_group("camps"):
			select_batiment(res.collider)
			return
	
	var sel = get_tree().get_nodes_in_group("soldats").filter(func(s): return s.get("est_selectionne"))
	if sel.is_empty(): deselect_batiment()

func select_batiment(bat):
	if batiment_selectionne: deselect_batiment()
	batiment_selectionne = bat
	if batiment_selectionne.has_method("set_selection"):
		batiment_selectionne.set_selection(true)
	batiment_selectionne_change.emit(batiment_selectionne)

func deselect_batiment():
	if batiment_selectionne:
		if batiment_selectionne.has_method("set_selection"):
			batiment_selectionne.set_selection(false)
		batiment_selectionne = null
		batiment_selectionne_change.emit(null)
