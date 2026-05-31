extends RefCounted
class_name ProjectileDamageUtils


static func apply_synced_damage(target: Node, damage: int, shooter: Variant, shooter_team: int) -> void:
	if not target.has_method("take_damage"):
		return
	var shooter_node: Node = shooter if is_instance_valid(shooter) else null
	if MapSession.is_online_match and OnlineGameSync.is_online_active():
		var attacker_id: int = -1
		if shooter_node != null and shooter_node.get("net_sync_id") != null:
			attacker_id = int(shooter_node.net_sync_id)
		if MapSession.is_local_team(shooter_team):
			var target_id: int = int(target.get("net_sync_id")) if target.get("net_sync_id") != null else -1
			if target_id >= 0:
				target.take_damage(damage, shooter_node, shooter_team)
				if attacker_id >= 0:
					OnlineGameSync.report_damage(attacker_id, target_id, damage, shooter_team)
				return
		if bool(target.get("net_remote_proxy")):
			return
	target.take_damage(damage, shooter_node, shooter_team)
