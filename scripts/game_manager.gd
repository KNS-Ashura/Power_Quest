extends Node

var cycle_time: float = 30.0
var cycle_gold_bonus: int = 100
var reinforcement_count: int = 2
var match_over: bool = false

@onready var global_timer = Timer.new()


func _ready() -> void:
	add_child(global_timer)
	global_timer.wait_time = cycle_time
	global_timer.timeout.connect(_on_global_timer_timeout)
	global_timer.start()
	call_deferred("_assign_initial_camps")


func init_match() -> void:
	match_over = false
	if not global_timer.is_stopped():
		global_timer.stop()
	global_timer.start()
	_assign_initial_camps()


func _assign_initial_camps() -> void:
	var all_camps = get_tree().get_nodes_in_group("camps")
	if all_camps.size() < 2:
		return

	all_camps.shuffle()

	var camps_per_player = max(1, all_camps.size() / 4)
	var index = 0

	for i in range(camps_per_player):
		all_camps[index]._capture_by_team(0)
		index += 1
		all_camps[index]._capture_by_team(1)
		index += 1

	while index < all_camps.size():
		all_camps[index]._capture_by_team(2)
		index += 1

	RegionManager.init_match()


func _process(_delta: float) -> void:
	if match_over:
		return

	var all_camps = get_tree().get_nodes_in_group("camps")
	if all_camps.size() == 0:
		return

	var player_count = 0
	var enemy_count = 0

	for camp in all_camps:
		var t = camp.get("team")
		if t == 0:
			player_count += 1
		elif t == 1:
			enemy_count += 1

	if player_count == 0:
		match_over = true
		print("DEFEAT")
	elif enemy_count == 0:
		match_over = true
		print("VICTORY")


func _on_global_timer_timeout() -> void:
	if match_over:
		return

	Economy.add_gold(cycle_gold_bonus)

	for camp in get_tree().get_nodes_in_group("camps"):
		if camp.get("team") == 0:
			camp.receive_reinforcements(reinforcement_count)
			break
