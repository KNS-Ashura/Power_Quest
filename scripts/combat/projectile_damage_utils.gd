extends RefCounted
class_name ProjectileDamageUtils


static func apply_synced_damage(cible: Node, degats: int, shooter: Node2D, shooter_team: int) -> void:
	if not cible.has_method("take_damage"):
		return
	if MapSession.is_online_match and OnlineGameSync.is_online_active():
		var attacker_id: int = -1
		if is_instance_valid(shooter) and shooter.get("net_sync_id") != null:
			attacker_id = int(shooter.net_sync_id)
		if MapSession.is_local_team(shooter_team):
			var target_id: int = int(cible.get("net_sync_id")) if cible.get("net_sync_id") != null else -1
			if target_id >= 0:
				cible.take_damage(degats, shooter, shooter_team)
				if attacker_id >= 0:
					OnlineGameSync.report_damage(attacker_id, target_id, degats, shooter_team)
				return
		if bool(cible.get("net_remote_proxy")):
			return
	cible.take_damage(degats, shooter, shooter_team)
