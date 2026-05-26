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
	if not MapSession.is_online_match:
		call_deferred("_assign_initial_camps")


func init_match() -> void:
	match_over = false
	if not global_timer.is_stopped():
		global_timer.stop()
	global_timer.start()
	if MapSession.is_online_match:
		OnlineMatch.begin_setup_after_main_loaded()
		return
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

	var local_camps := 0
	var hostile_camps := 0

	for camp in all_camps:
		var t: int = int(camp.get("team"))
		if MapSession.is_neutral_team(t):
			continue
		if MapSession.is_local_team(t):
			local_camps += 1
		else:
			hostile_camps += 1

	if local_camps == 0:
		match_over = true
		print("DEFEAT")
	elif hostile_camps == 0:
		match_over = true
		print("VICTORY")


func _on_global_timer_timeout() -> void:
	if match_over:
		return

	Economy.add_gold(cycle_gold_bonus)

	for camp in get_tree().get_nodes_in_group("camps"):
		if MapSession.is_local_team(int(camp.get("team"))):
			camp.receive_reinforcements(reinforcement_count)
			break
