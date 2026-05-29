extends Node

## Initialisation multijoueur autoritaire (serveur) : slots joueurs + répartition des camps.

signal setup_complete

const TEAM_NEUTRAL := 2


## Convertit un slot (0..N-1) en ID d'équipe en évitant l'ID neutre (2),
## pour supporter jusqu'à 8 joueurs sans collision avec le neutre.
## slots 0,1,2,3,4,5,6,7 -> équipes 0,1,3,4,5,6,7,8
func _slot_to_team(slot: int) -> int:
	return slot if slot < TEAM_NEUTRAL else slot + 1


func is_game_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


func begin_setup_after_main_loaded() -> void:
	if not MapSession.is_online_match:
		return
	if not is_game_server():
		return
	call_deferred("_server_setup")


func _server_setup() -> void:
	await get_tree().process_frame
	var camps := _sorted_camps()
	if camps.is_empty():
		push_warning("[OnlineMatch] Aucun camp sur la map.")
		return

	var peers: Array = multiplayer.get_peers()
	peers.sort()
	var player_count: int = peers.size()
	if player_count < 1:
		push_warning("[OnlineMatch] Aucun client connecté.")
		return

	MapSession.online_player_count = player_count

	var assignment_map := _distribute_camps_among_players(camps, player_count)
	var paths: PackedStringArray = PackedStringArray()
	var teams: PackedInt32Array = PackedInt32Array()
	var neutral_count := 0
	for camp in camps:
		var camp_team: int = int(assignment_map.get(camp, TEAM_NEUTRAL))
		paths.append(_camp_path(camp))
		teams.append(camp_team)
		if camp_team == TEAM_NEUTRAL:
			neutral_count += 1

	var team_names := _build_team_display_names(peers, player_count)
	MapSession.set_team_display_names(team_names)

	_apply_camp_assignments(paths, teams)
	print(
		"[OnlineMatch] %d joueurs, %d sites (%d neutres, 2 sites/joueur)."
		% [player_count, paths.size(), neutral_count]
	)

	for i in range(player_count):
		var peer_id: int = int(peers[i])
		var team_id: int = _slot_to_team(i)
		OnlineGameSync.register_peer_team(peer_id, team_id)
		rpc_match_player_setup.rpc_id(peer_id, team_id, player_count, paths, teams, team_names)

	MapSession.online_camps_ready = true
	setup_complete.emit()


## Chaque joueur démarre avec EXACTEMENT 2 sites : au moins 1 camp normal
## + un 2e site (camp OU port). Tous les autres sites restent NEUTRES (avec gardien).
func _distribute_camps_among_players(camps: Array, player_count: int) -> Dictionary:
	var assignments: Dictionary = {}
	# Tout neutre par défaut.
	for c in camps:
		assignments[c] = TEAM_NEUTRAL
	if player_count <= 0:
		return assignments

	# Sépare les camps normaux des ports.
	var regular: Array = []
	var ports: Array = []
	for c in camps:
		if c.has_method("is_port") and c.is_port():
			ports.append(c)
		else:
			regular.append(c)
	regular.shuffle()
	ports.shuffle()

	# 1er site garanti par joueur : un CAMP normal (repli sur port si trop peu de camps).
	var reg_idx: int = 0
	var port_idx: int = 0
	for slot in range(player_count):
		var team_id: int = _slot_to_team(slot)
		if reg_idx < regular.size():
			assignments[regular[reg_idx]] = team_id
			reg_idx += 1
		elif port_idx < ports.size():
			assignments[ports[port_idx]] = team_id
			port_idx += 1

	# 2e site par joueur : un site restant au hasard (camp ou port).
	var pool: Array = []
	pool.append_array(regular.slice(reg_idx, regular.size()))
	pool.append_array(ports.slice(port_idx, ports.size()))
	pool.shuffle()
	var pool_idx: int = 0
	for slot in range(player_count):
		if pool_idx < pool.size():
			assignments[pool[pool_idx]] = _slot_to_team(slot)
			pool_idx += 1

	return assignments


## Noms d'équipe indexés par ID d'équipe (pas par slot), car les IDs sautent le neutre.
func _build_team_display_names(peers: Array, player_count: int) -> PackedStringArray:
	var max_team: int = _slot_to_team(player_count - 1) if player_count > 0 else 0
	var names := PackedStringArray()
	names.resize(max_team + 1)
	for i in range(player_count):
		var peer_id: int = int(peers[i])
		names[_slot_to_team(i)] = NetworkSession.get_peer_display_name(peer_id)
	return names


func _sorted_camps() -> Array:
	var camps: Array = get_tree().get_nodes_in_group("camps")
	camps.sort_custom(
		func(a: Node, b: Node) -> bool:
			if a.global_position.x != b.global_position.x:
				return a.global_position.x < b.global_position.x
			return a.global_position.y < b.global_position.y
	)
	return camps


func _camp_path(camp: Node) -> String:
	return str(camp.get_path())


func _apply_camp_assignments(paths: PackedStringArray, teams: PackedInt32Array) -> void:
	for i in range(paths.size()):
		var camp: Node = get_node_or_null(NodePath(paths[i]))
		if camp != null and camp.has_method("_capture_by_team"):
			camp._capture_by_team(teams[i])


@rpc("authority", "call_remote", "reliable")
func rpc_match_player_setup(
	team: int,
	player_count: int,
	paths: PackedStringArray,
	teams: PackedInt32Array,
	team_names: PackedStringArray
) -> void:
	MapSession.local_team = team
	MapSession.online_player_count = player_count
	MapSession.set_team_display_names(team_names)
	_apply_camp_assignments(paths, teams)
	MapSession.online_camps_ready = true
	_refresh_all_camp_visuals()
	print("[OnlineMatch] Client prêt — équipe locale %d / %d joueurs." % [team, player_count])
	setup_complete.emit()


func _refresh_all_camp_visuals() -> void:
	for camp in get_tree().get_nodes_in_group("camps"):
		if camp.has_method("_update_groups_and_visuals"):
			camp._update_groups_and_visuals()
