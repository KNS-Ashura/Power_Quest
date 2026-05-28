extends Node

## Initialisation multijoueur autoritaire (serveur) : slots joueurs + répartition des camps.

signal setup_complete

const TEAM_NEUTRAL := 2
const NEUTRAL_SITES := 6


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
		"[OnlineMatch] %d joueurs, %d sites (%d neutres, ≥1 site/joueur)."
		% [player_count, paths.size(), neutral_count]
	)

	for i in range(player_count):
		var peer_id: int = int(peers[i])
		OnlineGameSync.register_peer_team(peer_id, i)
		rpc_match_player_setup.rpc_id(peer_id, i, player_count, paths, teams, team_names)

	MapSession.online_camps_ready = true
	setup_complete.emit()


## 6 sites neutres (camps ou ports) avec gardien ; le reste réparti entre les joueurs.
## Chaque joueur reçoit au moins un site ; les sites restants sont assignés aléatoirement.
func _distribute_camps_among_players(camps: Array, player_count: int) -> Dictionary:
	var assignments: Dictionary = {}
	var total: int = camps.size()
	var neutral_count: int = NEUTRAL_SITES
	if total < player_count + neutral_count:
		neutral_count = maxi(0, total - player_count)
		push_warning(
			"[OnlineMatch] Peu de sites (%d) pour %d joueurs + %d neutres — neutres réduits à %d."
			% [total, player_count, NEUTRAL_SITES, neutral_count]
		)

	var playable_count: int = total - neutral_count
	var shuffled: Array = camps.duplicate()
	shuffled.shuffle()

	var playable_sites: Array = shuffled.slice(0, playable_count)
	var neutral_sites: Array = shuffled.slice(playable_count, total)

	for site in neutral_sites:
		assignments[site] = TEAM_NEUTRAL

	if playable_sites.is_empty() or player_count <= 0:
		return assignments

	var guaranteed: int = mini(player_count, playable_sites.size())
	for i in range(guaranteed):
		assignments[playable_sites[i]] = i

	var extras: Array = []
	if playable_sites.size() > guaranteed:
		extras = playable_sites.slice(guaranteed, playable_sites.size())
	extras.shuffle()

	var recipient_slots: Array = []
	for slot in range(player_count):
		recipient_slots.append(slot)
	while recipient_slots.size() < extras.size():
		var batch: Array = range(player_count)
		batch.shuffle()
		recipient_slots.append_array(batch)
	recipient_slots.shuffle()
	recipient_slots = recipient_slots.slice(0, extras.size())

	for j in range(extras.size()):
		assignments[extras[j]] = int(recipient_slots[j])

	return assignments


func _build_team_display_names(peers: Array, player_count: int) -> PackedStringArray:
	var names := PackedStringArray()
	names.resize(player_count)
	for i in range(player_count):
		var peer_id: int = int(peers[i])
		names[i] = NetworkSession.get_peer_display_name(peer_id)
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
