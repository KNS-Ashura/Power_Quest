extends Node

var temps_cycle : float = 30.0
var bonus_or : int = 100
var nb_soldats_renfort : int = 2
var fin_de_partie : bool = false

@onready var timer_global = Timer.new()

var _assignation_faite: bool = false
var _envoi_fait: bool = false

func _ready():
	add_child(timer_global)
	timer_global.timeout.connect(_on_timer_global_timeout)

var _debug_printed: bool = false

func _process(_delta):
	if not _assignation_faite and ServerConnection.game_started:
		var camps = get_tree().get_nodes_in_group("camps")
		if not _debug_printed:
			_debug_printed = true
			print("[GM] game_started=true | camps=", camps.size(), " | local_side=", ServerConnection.local_side, " | lobby_player_count=", ServerConnection.lobby_player_count, " | is_host=", ServerConnection.is_local_host())
		if camps.size() >= 2 and not _envoi_fait:
			_envoi_fait = true
			# Assignation déterministe locale pour les deux clients (solo et multi)
			_assigner_camps_local()
			# L'hôte envoie aussi via réseau pour sync des arrivants tardifs
			if ServerConnection.has_valid_session() and ServerConnection.is_local_host():
				_assigner_et_envoyer_camps()

	if fin_de_partie or not _assignation_faite:
		return

	var tous_les_camps = get_tree().get_nodes_in_group("camps")
	if tous_les_camps.size() == 0:
		return

	var equipes_actives := {}
	for camp in tous_les_camps:
		var eq = camp.get("equipe")
		if eq != null and eq != -1:
			equipes_actives[eq] = true

	if equipes_actives.size() <= 1:
		fin_de_partie = true
		if equipes_actives.size() == 1 and equipes_actives.has(ServerConnection.local_side):
			print("VICTOIRE")
		else:
			print("DEFAITE")

## Assignation déterministe locale : même seed + même tri = même résultat sur tous les clients.
func _assigner_camps_local():
	var tous_les_camps = get_tree().get_nodes_in_group("camps")
	print("[GM] _assigner_camps_local | camps=", tous_les_camps.size(), " | seed=", ServerConnection.game_start_seed, " | nb_joueurs=", ServerConnection.lobby_player_count)
	if tous_les_camps.size() < 1:
		return

	# Tri par nom pour garantir le même ordre sur tous les clients
	tous_les_camps.sort_custom(func(a, b): return a.name < b.name)

	var rng = RandomNumberGenerator.new()
	rng.seed = ServerConnection.game_start_seed
	for i in range(tous_les_camps.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = tous_les_camps[i]
		tous_les_camps[i] = tous_les_camps[j]
		tous_les_camps[j] = tmp

	# En multi, players_data est la source la plus fiable (peuplé depuis lobby_state)
	var nb_joueurs: int
	if ServerConnection.has_valid_session() and ServerConnection.players_data.size() >= 2:
		nb_joueurs = ServerConnection.players_data.size()
	else:
		nb_joueurs = max(ServerConnection.lobby_player_count, 1)
	print("[GM] nb_joueurs résolu=", nb_joueurs, " (players_data=", ServerConnection.players_data.size(), " lobby_count=", ServerConnection.lobby_player_count, ")")
	for i in range(min(nb_joueurs, tous_les_camps.size())):
		tous_les_camps[i]._etre_capture_par_equipe(i, false)  # false = pas de broadcast réseau (assignation initiale)
	for i in range(nb_joueurs, tous_les_camps.size()):
		tous_les_camps[i]._etre_capture_par_equipe(-1, false)

	on_camps_assignes()

## Envoi réseau par l'hôte pour synchroniser les arrivants tardifs (non critique pour le démarrage).
func _assigner_et_envoyer_camps():
	if not ServerConnection.is_socket_ready_for_match():
		print("[GM] WARN: socket pas prête pour l'envoi réseau (assignation locale déjà faite)")
		return

	var tous_les_camps = get_tree().get_nodes_in_group("camps")
	if tous_les_camps.size() < 1:
		return

	# Même tri que _assigner_camps_local pour cohérence
	tous_les_camps.sort_custom(func(a, b): return a.name < b.name)

	var rng = RandomNumberGenerator.new()
	rng.seed = ServerConnection.game_start_seed
	for i in range(tous_les_camps.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = tous_les_camps[i]
		tous_les_camps[i] = tous_les_camps[j]
		tous_les_camps[j] = tmp

	var nb_joueurs: int
	if ServerConnection.players_data.size() >= 2:
		nb_joueurs = ServerConnection.players_data.size()
	else:
		nb_joueurs = max(ServerConnection.lobby_player_count, 1)
	var assignments = []
	for i in range(tous_les_camps.size()):
		var eq = i if i < nb_joueurs else -1
		assignments.append({"name": tous_les_camps[i].name, "equipe": eq})

	print("[GM] Envoi camp_assign réseau | nb_joueurs=", nb_joueurs)
	var cmd = {"type": "camp_assign", "assignments": assignments}
	ServerConnection.socket.send_match_state_async(
		ServerConnection.current_match_id,
		ServerConnection.OP_COMMAND,
		JSON.stringify(cmd)
	)

## Appelé par NetworkAuthority ou localement quand les assignations sont appliquées.
func on_camps_assignes():
	_assignation_faite = true
	if timer_global.is_inside_tree():
		timer_global.wait_time = temps_cycle
		timer_global.start()
	print("[GM] Assignation camps terminée | _assignation_faite=true")

func _on_timer_global_timeout():
	if fin_de_partie:
		return

	Economie.ajouter_argent(bonus_or)

	for camp in get_tree().get_nodes_in_group("camps"):
		if camp.get("equipe") == ServerConnection.local_side:
			camp.recevoir_renforts(nb_soldats_renfort)
			break
