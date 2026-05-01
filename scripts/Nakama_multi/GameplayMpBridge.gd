extends Node
## Pont réseau : synchronise les unités (snapshot 4x/s) et les captures de camps.

const SCENE_SOLDAT = preload("res://scenes/personnages/player/soldat.tscn")

var _catalogue_stats: Dictionary = {}
var _sync_counter: int = 0
var _unites_distantes: Dictionary = {}   # sync_id (int) → ghost Node2D
var _timer_sync: Timer

func _ready():
	_catalogue_stats = {
		0: preload("res://scripts/resources/infanterie.tres"),
		1: preload("res://scripts/resources/archer.tres"),
		2: preload("res://scripts/resources/lourd.tres"),
		3: preload("res://scripts/resources/support.tres"),
		4: preload("res://scripts/resources/heal.tres"),
		5: preload("res://scripts/resources/anti_armor.tres"),
		6: preload("res://scripts/resources/mortar.tres"),
	}
	if not ServerConnection.match_message.is_connected(_on_match_message):
		ServerConnection.match_message.connect(_on_match_message)

	_timer_sync = Timer.new()
	_timer_sync.wait_time = 0.25
	_timer_sync.timeout.connect(_envoyer_snapshot_unites)
	add_child(_timer_sync)
	_timer_sync.start()

# ---------------------------------------------------------------------------
# Snapshot des unités locales → envoi toutes les 0.25 s
# ---------------------------------------------------------------------------

func _envoyer_snapshot_unites() -> void:
	if not ServerConnection.game_started: return
	if not ServerConnection.is_socket_ready_for_match(): return
	if get_tree().get_nodes_in_group("camps").is_empty(): return

	var units_data: Array = []
	for soldat in get_tree().get_nodes_in_group("soldats"):
		if not is_instance_valid(soldat): continue
		if soldat.get_meta("is_gardien", false): continue  # gardiens gérés via camp_capture
		if soldat.get_meta("is_ghost", false): continue    # ne pas re-diffuser les ghosts reçus

		var sync_id: int = soldat.get_meta("sync_id", -1)
		if sync_id == -1:
			sync_id = ServerConnection.local_side * 1000000 + _sync_counter
			_sync_counter = (_sync_counter + 1) % 999999
			soldat.set_meta("sync_id", sync_id)

		units_data.append({
			"id": sync_id,
			"x": roundi(soldat.global_position.x),
			"y": roundi(soldat.global_position.y),
			"eq": soldat.get("equipe", ServerConnection.local_side),
			"t":  soldat.get_meta("stats_type", 0)
		})

	var cmd := {"type": "units_snapshot", "units": units_data}
	ServerConnection.socket.send_match_state_async(
		ServerConnection.current_match_id,
		ServerConnection.OP_COMMAND,
		JSON.stringify(cmd)
	)

# ---------------------------------------------------------------------------
# Capture de camps → appelé par camp.gd lors d'une capture en combat
# ---------------------------------------------------------------------------

func envoyer_capture_camp(camp_name: String, equipe: int) -> void:
	if not ServerConnection.is_socket_ready_for_match(): return
	var cmd := {"type": "camp_capture", "camp_name": camp_name, "equipe": equipe}
	ServerConnection.socket.send_match_state_async(
		ServerConnection.current_match_id,
		ServerConnection.OP_COMMAND,
		JSON.stringify(cmd)
	)
	print("[GPB] Envoi camp_capture | camp=", camp_name, " equipe=", equipe)

# ---------------------------------------------------------------------------
# Réception de tous les messages réseau
# ---------------------------------------------------------------------------

func _on_match_message(state: NakamaRTAPI.MatchData) -> void:
	if state.op_code != ServerConnection.OP_COMMAND: return
	var data = ServerConnection.parse_match_state_data(state.data)
	if data == null or typeof(data) != TYPE_DICTIONARY: return

	# Ignorer les messages que j'ai moi-même envoyés (le serveur rebroadcast à tous)
	var net = data.get("_net", null)
	if net != null:
		var from_uid := str(net.get("from_user_id", ""))
		if from_uid != "" and from_uid == ServerConnection.get_local_user_id():
			return

	match data.get("type", ""):
		"units_snapshot": _appliquer_snapshot(data)
		"camp_capture":   _appliquer_capture_camp(data)

# ---------------------------------------------------------------------------
# Application du snapshot d'unités
# ---------------------------------------------------------------------------

func _appliquer_snapshot(data: Dictionary) -> void:
	if get_tree().get_nodes_in_group("camps").is_empty(): return

	var received_ids := {}

	for u in data.get("units", []):
		var sync_id := int(u.get("id", -1))
		if sync_id == -1: continue
		var pos   := Vector2(float(u.get("x", 0)), float(u.get("y", 0)))
		var eq    := int(u.get("eq", -1))
		var tid   := int(u.get("t", 0))
		received_ids[sync_id] = true

		# Nettoyer les ghosts invalides
		if _unites_distantes.has(sync_id) and not is_instance_valid(_unites_distantes[sync_id]):
			_unites_distantes.erase(sync_id)

		if _unites_distantes.has(sync_id):
			_unites_distantes[sync_id].global_position = pos
		else:
			_creer_ghost(sync_id, pos, eq, tid)

	# Supprimer les ghosts dont l'unité n'apparaît plus dans le snapshot (unité morte)
	var a_supprimer: Array = []
	for sync_id in _unites_distantes:
		if not received_ids.has(sync_id):
			a_supprimer.append(sync_id)
	for sync_id in a_supprimer:
		if is_instance_valid(_unites_distantes[sync_id]):
			_unites_distantes[sync_id].queue_free()
		_unites_distantes.erase(sync_id)

func _creer_ghost(sync_id: int, pos: Vector2, eq: int, type_id: int) -> void:
	var scene_racine = get_tree().current_scene
	if scene_racine == null: return

	var ghost = SCENE_SOLDAT.instantiate()
	ghost.stats = _catalogue_stats.get(type_id, _catalogue_stats[0])
	ghost.equipe = eq
	ghost.set_meta("is_ghost", true)
	ghost.set_meta("sync_id", sync_id)

	# Désactiver les collisions : le ghost est purement visuel,
	# il ne participe pas au combat local.
	ghost.collision_layer = 0
	ghost.collision_mask  = 0

	if eq != ServerConnection.local_side and eq != -1:
		ghost.add_to_group("ennemis")

	scene_racine.add_child(ghost)
	ghost.global_position = pos

	_unites_distantes[sync_id] = ghost

# ---------------------------------------------------------------------------
# Application d'une capture de camp
# ---------------------------------------------------------------------------

func _appliquer_capture_camp(data: Dictionary) -> void:
	var camp_name := str(data.get("camp_name", ""))
	var equipe    := int(data.get("equipe", -1))
	for camp in get_tree().get_nodes_in_group("camps"):
		if camp.name == camp_name:
			if camp.get("equipe") != equipe:
				print("[GPB] Réception camp_capture | camp=", camp_name, " equipe=", equipe)
				camp._etre_capture_par_equipe(equipe, false)
			return
	print("[GPB] WARN: camp introuvable: ", camp_name)
