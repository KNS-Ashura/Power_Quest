extends CanvasLayer

@onready var btn_heal: Button = $Control/Panel/HBoxContainer/BtnHeal
@onready var btn_boost: Button = $Control/Panel/HBoxContainer/BtnBoost

const RAYON_EFFET_SORT: float = 150.0
const DUREE_AFFICHAGE_ZONE: float = 0.6
const NB_POINTS_CERCLE: int = 48
const COULEUR_HEAL_BORD: Color = Color(0.2, 1.0, 0.2, 1.0)
const COULEUR_HEAL_FOND: Color = Color(0.2, 1.0, 0.2, 0.2)
const COULEUR_BOOST_BORD: Color = Color(0.25, 0.55, 1.0, 1.0)
const COULEUR_BOOST_FOND: Color = Color(0.25, 0.55, 1.0, 0.2)

var _nb_healers_selectionnes: int = 0
var _nb_supports_selectionnes: int = 0

func _ready():
	btn_heal.disabled = true
	btn_boost.disabled = true

func _process(_delta):
	_refresh_etat_boutons()

func _refresh_etat_boutons():
	var healers := 0
	var supports := 0

	for unite in get_tree().get_nodes_in_group("soldats"):
		if not unite.get("est_selectionne"):
			continue
		if unite.get("equipe") != 0:
			continue
		if not unite.get("stats"):
			continue

		match int(unite.stats.type_unite):
			3:
				supports += 1
			4:
				healers += 1

	if healers == _nb_healers_selectionnes and supports == _nb_supports_selectionnes:
		return

	_nb_healers_selectionnes = healers
	_nb_supports_selectionnes = supports

	btn_heal.disabled = _nb_healers_selectionnes <= 0
	btn_boost.disabled = _nb_supports_selectionnes <= 0

func _on_btn_heal_pressed():
	var healers = _get_unites_selectionnees_par_type(4)
	for healer in healers:
		if healer.has_method("lancer_sort"):
			healer.lancer_sort()
		_afficher_zone_effet(healer.global_position, RAYON_EFFET_SORT, COULEUR_HEAL_BORD, COULEUR_HEAL_FOND)

	print(str(_nb_healers_selectionnes) + " healer(s) selectionne(s), pouvoir Heal active")

func _on_btn_boost_pressed():
	var supports = _get_unites_selectionnees_par_type(3)
	for support in supports:
		if support.has_method("lancer_sort"):
			support.lancer_sort()
		_afficher_zone_effet(support.global_position, RAYON_EFFET_SORT, COULEUR_BOOST_BORD, COULEUR_BOOST_FOND)

	print(str(_nb_supports_selectionnes) + " support(s) selectionne(s), pouvoir Boost active")

func _get_unites_selectionnees_par_type(type_unite: int) -> Array:
	var resultat: Array = []
	for unite in get_tree().get_nodes_in_group("soldats"):
		if not unite.get("est_selectionne"):
			continue
		if unite.get("equipe") != 0:
			continue
		if not unite.get("stats"):
			continue
		if int(unite.stats.type_unite) == type_unite:
			resultat.append(unite)
	return resultat

func _afficher_zone_effet(position_monde: Vector2, rayon: float, couleur_bord: Color, couleur_fond: Color):
	var scene = get_tree().current_scene
	if scene == null:
		return

	var zone = Node2D.new()
	zone.global_position = position_monde

	var contour = Line2D.new()
	contour.width = 4.0
	contour.default_color = couleur_bord
	contour.closed = true

	var remplissage = Polygon2D.new()
	remplissage.color = couleur_fond

	var points: PackedVector2Array = []
	for i in range(NB_POINTS_CERCLE):
		var angle = TAU * float(i) / float(NB_POINTS_CERCLE)
		points.append(Vector2(cos(angle), sin(angle)) * rayon)

	contour.points = points
	remplissage.polygon = points

	zone.add_child(remplissage)
	zone.add_child(contour)
	scene.add_child(zone)

	var tween = create_tween()
	tween.tween_property(zone, "modulate:a", 0.0, DUREE_AFFICHAGE_ZONE)
	tween.finished.connect(func(): zone.queue_free())
