extends Node

## Initialisation multijoueur autoritaire (serveur) : slots joueurs + répartition des camps.

signal setup_complete

const TEAM_NEUTRAL := 2


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

	var per_player: int = maxi(1, camps.size() / player_count)
	var paths: PackedStringArray = PackedStringArray()
	var teams: PackedInt32Array = PackedInt32Array()
	var index: int = 0

	for slot in range(player_count):
		for _j in range(per_player):
			if index >= camps.size():
				break
			paths.append(_camp_path(camps[index]))
			teams.append(slot)
			index += 1

	while index < camps.size():
		paths.append(_camp_path(camps[index]))
		teams.append(TEAM_NEUTRAL)
		index += 1

	_apply_camp_assignments(paths, teams)
	print(
		"[OnlineMatch] %d joueurs, %d camps (%d/camp par joueur, %d neutres)."
		% [player_count, paths.size(), per_player, paths.size() - player_count * per_player]
	)

	for i in range(player_count):
		var peer_id: int = int(peers[i])
		OnlineGameSync.register_peer_team(peer_id, i)
		rpc_match_player_setup.rpc_id(peer_id, i, player_count, paths, teams)

	MapSession.online_camps_ready = true
	setup_complete.emit()


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
	teams: PackedInt32Array
) -> void:
	MapSession.local_team = team
	MapSession.online_player_count = player_count
	_apply_camp_assignments(paths, teams)
	MapSession.online_camps_ready = true
	_refresh_all_camp_visuals()
	print("[OnlineMatch] Client prêt — équipe locale %d / %d joueurs." % [team, player_count])
	setup_complete.emit()


func _refresh_all_camp_visuals() -> void:
	for camp in get_tree().get_nodes_in_group("camps"):
		if camp.has_method("_update_groups_and_visuals"):
			camp._update_groups_and_visuals()
