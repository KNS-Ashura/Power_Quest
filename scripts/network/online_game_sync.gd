extends Node

## Sync multijoueur : spawn, ordres, position, dégâts.

const TEAM_NEUTRAL := 2
const SYNC_INTERVAL := 0.12

## Types de sort synchronisés (visuels + effets sur cibles connues).
const SPELL_INVULN := 0
const SPELL_BOOST := 1
const SPELL_MORTAR := 2
const SPELL_ANTI_ARMOR := 3
const SPELL_HEAL_PROJECTILE := 4

var _peer_to_team: Dictionary = {}
var _next_sync_id: int = 1
var _owner_peer_for_id: Dictionary = {}
var _units_by_sync_id: Dictionary = {}
var _sync_accum: float = 0.0
var _pending_by_token: Dictionary = {}
var _next_spawn_token: int = 1
var _captured_camp_state: Dictionary = {}


func reset() -> void:
	_peer_to_team.clear()
	_owner_peer_for_id.clear()
	_units_by_sync_id.clear()
	_next_sync_id = 1
	_sync_accum = 0.0
	_pending_by_token.clear()
	_next_spawn_token = 1
	_captured_camp_state.clear()


func notify_unit_spawned(camp: Node, unit: Node, unite_id: int, spawn_pos: Vector2) -> void:
	if not is_online_active() or camp == null or unit == null:
		return
	if multiplayer.is_server():
		return
	# Token unique pour apparier l'unité locale à son sync_id même si plusieurs
	# unités sont spawnées avant la réponse du serveur.
	var token: int = _next_spawn_token
	_next_spawn_token += 1
	_pending_by_token[token] = unit
	rpc_report_unit_spawn.rpc_id(
		1, str(camp.get_path()), unite_id, spawn_pos, int(camp.get("team")), token
	)


func _resolve_node(path: String) -> Node:
	if path.is_empty():
		return null
	var node: Node = get_tree().root.get_node_or_null(NodePath(path))
	if node != null:
		return node
	if path.begins_with("/root/"):
		node = get_tree().root.get_node_or_null(NodePath(path.trim_prefix("/root")))
		if node != null:
			return node
	var scene: Node = get_tree().current_scene
	if scene != null and not path.begins_with("/"):
		return scene.get_node_or_null(NodePath(path))
	return null


func _find_camp_for_spawn(camp_path: String, spawn_pos: Vector2, team_id: int) -> Node:
	var camp: Node = _resolve_node(camp_path)
	if camp != null:
		return camp
	for c in get_tree().get_nodes_in_group("camps"):
		if int(c.get("team")) == team_id:
			if c.global_position.distance_to(spawn_pos) < 500.0:
				return c
	return null


func register_peer_team(peer_id: int, team: int) -> void:
	_peer_to_team[peer_id] = team


func peer_team(peer_id: int) -> int:
	return int(_peer_to_team.get(peer_id, -1))


func is_online_active() -> bool:
	return MapSession.is_online_match and multiplayer.multiplayer_peer != null


func register_unit(sync_id: int, unit: Node) -> void:
	if sync_id < 0 or unit == null:
		return
	_units_by_sync_id[sync_id] = unit


func unregister_unit(sync_id: int) -> void:
	_units_by_sync_id.erase(sync_id)


func get_unit(sync_id: int) -> Node:
	if sync_id < 0:
		return null
	var u: Variant = _units_by_sync_id.get(sync_id)
	if u is Node and is_instance_valid(u):
		return u as Node
	_units_by_sync_id.erase(sync_id)
	return null


func _process(delta: float) -> void:
	if not is_online_active() or ServerMode.is_dedicated_server:
		return
	if multiplayer.is_server():
		return
	_sync_accum += delta
	if _sync_accum < SYNC_INTERVAL:
		return
	_sync_accum = 0.0
	_envoyer_snapshots_locaux()


func _unit_hp(unit: Node) -> int:
	if unit != null and "current_hp" in unit:
		return int(unit.get("current_hp"))
	return 0


func _unit_velocity(unit: Node) -> Vector2:
	if unit is CharacterBody2D:
		return (unit as CharacterBody2D).velocity
	return Vector2.ZERO


func _envoyer_snapshots_locaux() -> void:
	for sync_id in _units_by_sync_id.keys():
		var unit: Node = _units_by_sync_id[sync_id]
		if not is_instance_valid(unit):
			continue
		if bool(unit.get("net_remote_proxy")):
			continue
		if not MapSession.is_local_team(int(unit.get("team"))):
			continue
		if unit.get("net_sync_id") == null or int(unit.get("net_sync_id")) < 0:
			continue
		var hp: int = _unit_hp(unit)
		var vel: Vector2 = _unit_velocity(unit)
		rpc_report_unit_state.rpc_id(
			1, int(unit.get("net_sync_id")), unit.global_position, vel, hp
		)


# --- Spawn ---

@rpc("any_peer", "reliable")
func rpc_report_unit_spawn(
	camp_path: String, unite_id: int, spawn_pos: Vector2, equipe: int, token: int
) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var expected_team: int = peer_team(sender)
	if expected_team < 0 or int(equipe) != expected_team:
		push_warning(
			"[OnlineGameSync] Spawn refusé peer %d (équipe attendue %d, reçue %d)."
			% [sender, expected_team, equipe]
		)
		return
	var sync_id: int = _next_sync_id
	_next_sync_id += 1
	_owner_peer_for_id[sync_id] = sender
	rpc_assign_sync_id.rpc_id(sender, sync_id, token)
	for peer_id in multiplayer.get_peers():
		if peer_id == sender:
			continue
		rpc_spawn_unit.rpc_id(peer_id, camp_path, unite_id, spawn_pos, equipe, sync_id)


@rpc("authority", "call_remote", "reliable")
func rpc_assign_sync_id(sync_id: int, token: int) -> void:
	if ServerMode.is_dedicated_server:
		return
	var unit: Node = _pending_by_token.get(token)
	_pending_by_token.erase(token)
	if not is_instance_valid(unit):
		push_warning("[OnlineGameSync] Unité locale introuvable pour sync_id %d (token %d)." % [sync_id, token])
		return
	unit.net_sync_id = sync_id
	unit.net_remote_proxy = false
	register_unit(sync_id, unit)


@rpc("authority", "call_remote", "reliable")
func rpc_spawn_unit(
	camp_path: String, unite_id: int, spawn_pos: Vector2, equipe: int, sync_id: int
) -> void:
	if ServerMode.is_dedicated_server:
		return
	var camp: Node = _find_camp_for_spawn(camp_path, spawn_pos, equipe)
	if camp == null or not camp.has_method("spawn_unite_reseau"):
		push_warning("[OnlineGameSync] Camp introuvable pour spawn: %s" % camp_path)
		return
	var unit: Node = camp.spawn_unite_reseau(unite_id, spawn_pos, equipe, sync_id)
	if unit != null:
		register_unit(sync_id, unit)


# --- Ordres (déplacement / attaque) ---

func report_player_orders(unit_sync_ids: Array, move_to: Vector2, attack_sync_id: int) -> void:
	if not is_online_active() or unit_sync_ids.is_empty():
		return
	if multiplayer.is_server():
		return
	rpc_report_orders.rpc_id(1, unit_sync_ids, move_to, attack_sync_id)


@rpc("any_peer", "reliable")
func rpc_report_orders(unit_sync_ids: Array, move_to: Vector2, attack_sync_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	for peer_id in multiplayer.get_peers():
		if peer_id == sender:
			continue
		rpc_apply_orders.rpc_id(peer_id, unit_sync_ids, move_to, attack_sync_id)


@rpc("authority", "call_remote", "reliable")
func rpc_apply_orders(unit_sync_ids: Array, move_to: Vector2, attack_sync_id: int) -> void:
	if ServerMode.is_dedicated_server:
		return
	var cible: Node = get_unit(attack_sync_id)
	for sid in unit_sync_ids:
		var unit: Node = get_unit(int(sid))
		if unit == null or not unit.has_method("apply_network_order"):
			continue
		unit.apply_network_order(move_to, cible)


# --- Position (snapshots) ---

@rpc("any_peer", "unreliable")
func rpc_report_unit_state(sync_id: int, pos: Vector2, vel: Vector2, hp: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if int(_owner_peer_for_id.get(sync_id, -1)) != sender:
		return
	for peer_id in multiplayer.get_peers():
		if peer_id == sender:
			continue
		rpc_remote_unit_state.rpc_id(peer_id, sync_id, "", -1, pos, vel, hp, false)


@rpc("authority", "call_remote", "unreliable")
func rpc_remote_unit_state(
	sync_id: int,
	_unit_path: String,
	equipe: int,
	pos: Vector2,
	vel: Vector2,
	hp: int,
	is_spawn_hint: bool
) -> void:
	if ServerMode.is_dedicated_server:
		return
	var unit: Node = get_unit(sync_id)
	if unit == null and is_spawn_hint:
		return
	if unit == null:
		return
	if unit.has_method("apply_network_state"):
		unit.apply_network_state(pos, vel, hp)


# --- Combat ---

func report_damage(attacker_sync_id: int, target_sync_id: int, damage: int, attacker_team: int) -> void:
	if not is_online_active() or target_sync_id < 0:
		return
	if multiplayer.is_server():
		return
	rpc_report_damage.rpc_id(1, attacker_sync_id, target_sync_id, damage, attacker_team)


@rpc("any_peer", "reliable")
func rpc_report_damage(
	attacker_sync_id: int, target_sync_id: int, damage: int, attacker_team: int
) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if peer_team(sender) != attacker_team:
		return
	if int(_owner_peer_for_id.get(attacker_sync_id, -1)) != sender:
		return
	for peer_id in multiplayer.get_peers():
		if peer_id == sender:
			continue
		rpc_apply_damage.rpc_id(peer_id, target_sync_id, damage, attacker_team)


@rpc("authority", "call_remote", "reliable")
func rpc_apply_damage(target_sync_id: int, damage: int, attacker_team: int) -> void:
	if ServerMode.is_dedicated_server:
		return
	var unit: Node = get_unit(target_sync_id)
	if unit != null and unit.has_method("take_damage_network_remote"):
		unit.take_damage_network_remote(damage, attacker_team)


func report_heal(caster_sync_id: int, target_sync_id: int, amount: int) -> void:
	if not is_online_active() or target_sync_id < 0 or amount <= 0:
		return
	if multiplayer.is_server():
		return
	rpc_report_heal.rpc_id(1, caster_sync_id, target_sync_id, amount)


@rpc("any_peer", "reliable")
func rpc_report_heal(caster_sync_id: int, target_sync_id: int, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if int(_owner_peer_for_id.get(caster_sync_id, -1)) != sender:
		return
	for peer_id in multiplayer.get_peers():
		if peer_id == sender:
			continue
		rpc_apply_heal.rpc_id(peer_id, caster_sync_id, target_sync_id, amount)


@rpc("authority", "call_remote", "reliable")
func rpc_apply_heal(caster_sync_id: int, target_sync_id: int, amount: int) -> void:
	if ServerMode.is_dedicated_server:
		return
	var unit: Node = get_unit(target_sync_id)
	if unit != null and unit.has_method("apply_heal_network_remote"):
		unit.apply_heal_network_remote(amount, caster_sync_id)


func report_spell_cast(
	caster_sync_id: int, spell_type: int, target_sync_ids: Array, params: Dictionary = {}
) -> void:
	if not is_online_active() or caster_sync_id < 0:
		return
	if multiplayer.is_server():
		return
	rpc_report_spell_cast.rpc_id(1, caster_sync_id, spell_type, target_sync_ids, params)


@rpc("any_peer", "reliable")
func rpc_report_spell_cast(
	caster_sync_id: int, spell_type: int, target_sync_ids: Array, params: Dictionary
) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if int(_owner_peer_for_id.get(caster_sync_id, -1)) != sender:
		return
	for peer_id in multiplayer.get_peers():
		if peer_id == sender:
			continue
		rpc_apply_spell_cast.rpc_id(peer_id, caster_sync_id, spell_type, target_sync_ids, params)


@rpc("authority", "call_remote", "reliable")
func rpc_apply_spell_cast(
	caster_sync_id: int, spell_type: int, target_sync_ids: Array, params: Dictionary
) -> void:
	if ServerMode.is_dedicated_server:
		return
	var caster: Node = get_unit(caster_sync_id)
	if caster != null and caster.has_method("apply_spell_network_remote"):
		caster.apply_spell_network_remote(spell_type, target_sync_ids, params)


func report_unit_death(sync_id: int) -> void:
	if not is_online_active() or sync_id < 0:
		return
	if multiplayer.is_server():
		return
	rpc_report_death.rpc_id(1, sync_id)


@rpc("any_peer", "reliable")
func rpc_report_death(sync_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if int(_owner_peer_for_id.get(sync_id, -1)) != sender:
		return
	_owner_peer_for_id.erase(sync_id)
	for peer_id in multiplayer.get_peers():
		rpc_apply_death.rpc_id(peer_id, sync_id)


@rpc("authority", "call_remote", "reliable")
func rpc_apply_death(sync_id: int) -> void:
	if ServerMode.is_dedicated_server:
		return
	var unit: Node = get_unit(sync_id)
	unregister_unit(sync_id)
	if unit != null and is_instance_valid(unit) and not unit.is_queued_for_deletion():
		if unit.has_method("force_network_death"):
			unit.force_network_death()
		else:
			unit.queue_free()


# --- Capture de camp (mort du gardien) ---

func report_camp_capture(camp_path: String, new_team: int) -> void:
	if not is_online_active() or camp_path.is_empty():
		return
	if multiplayer.is_server():
		return
	rpc_report_camp_capture.rpc_id(1, camp_path, new_team)


@rpc("any_peer", "reliable")
func rpc_report_camp_capture(camp_path: String, new_team: int) -> void:
	if not multiplayer.is_server():
		return
	# Anti-doublon : ignore les rapports identiques (plusieurs clients peuvent voir
	# le même gardien mourir), mais laisse passer un vrai changement de propriétaire.
	if int(_captured_camp_state.get(camp_path, -99)) == new_team:
		return
	_captured_camp_state[camp_path] = new_team
	for peer_id in multiplayer.get_peers():
		rpc_apply_camp_capture.rpc_id(peer_id, camp_path, new_team)


@rpc("authority", "call_remote", "reliable")
func rpc_apply_camp_capture(camp_path: String, new_team: int) -> void:
	if ServerMode.is_dedicated_server:
		return
	var camp: Node = _resolve_node(camp_path)
	if camp == null:
		for c in get_tree().get_nodes_in_group("camps"):
			if str(c.get_path()) == camp_path:
				camp = c
				break
	if camp == null or not camp.has_method("_capture_by_team"):
		return
	if int(camp.get("team")) != new_team:
		camp._capture_by_team(new_team)
