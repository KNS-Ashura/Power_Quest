extends Node

## Assignations reçues avant que les camps soient prêts dans la scène.
var _pending_camp_assignments: Array = []

func _ready():
	if not ServerConnection.match_message.is_connected(_on_match_message):
		ServerConnection.match_message.connect(_on_match_message)

func _process(_delta):
	if _pending_camp_assignments.size() > 0:
		var camps = get_tree().get_nodes_in_group("camps")
		if camps.size() >= 2:
			_appliquer_assignation(_pending_camp_assignments)
			_pending_camp_assignments.clear()

func _on_match_message(state: NakamaRTAPI.MatchData) -> void:
	if state.op_code != ServerConnection.OP_COMMAND:
		return
	var data = ServerConnection.parse_match_state_data(state.data)
	if data == null or typeof(data) != TYPE_DICTIONARY:
		return
	match data.get("type", ""):
		"camp_assign":
			var assignments = data.get("assignments", [])
			var camps = get_tree().get_nodes_in_group("camps")
			if camps.size() >= 2:
				_appliquer_assignation(assignments)
			else:
				_pending_camp_assignments = assignments
				print("[NA] camp_assign reçu en attente (camps pas encore prêts)")

func _appliquer_assignation(assignments: Array) -> void:
	if GameManager.get("_assignation_faite"):
		print("[NA] Assignation déjà faite localement, message réseau ignoré")
		return
	print("[NA] Application de ", assignments.size(), " assignations")
	var camp_dict = {}
	for c in get_tree().get_nodes_in_group("camps"):
		camp_dict[c.name] = c

	for a in assignments:
		var cname = str(a.get("name", ""))
		var eq = int(a.get("equipe", -1))
		if camp_dict.has(cname):
			camp_dict[cname]._etre_capture_par_equipe(eq, false)  # false = pas de re-broadcast
		else:
			print("[NA] WARN: camp introuvable: ", cname)

	GameManager.on_camps_assignes()
