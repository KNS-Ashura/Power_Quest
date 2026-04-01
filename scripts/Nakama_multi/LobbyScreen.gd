extends Control

@onready var label_code: Label = %Label_CodeRecu
@onready var input_saisie: LineEdit = %LineEdit_SaisieCode
@onready var status_label: Label = %Label_Status_Lobby


@onready var btn_creer: Button = %Button_creer
@onready var btn_join: Button = %Button_join
@onready var btn_copy: Button = %Button_copy

enum State { IDLE, BUSY, IN_LOBBY }
var _state = State.IDLE

func _ready():
	await get_tree().process_frame 
	
	if ServerConnection.socket == null:
		get_tree().change_scene_to_file("res://scene_login.tscn")
		return

	if not ServerConnection.socket.received_match_state.is_connected(_on_match_state):
		ServerConnection.socket.received_match_state.connect(_on_match_state)
	
	_update_ui(State.IDLE)

func _on_button_creer_pressed():
	_update_ui(State.BUSY)
	status_label.text = "Génération du code..."
	var res = await LobbyManager.create_lobby()
	
	if res["success"]:
		label_code.text = res["code"]
		status_label.text = "Salon créé ! Partagez le code."
		_update_ui(State.IN_LOBBY)
	else:
		status_label.text = "Erreur : " + res["msg"]
		_update_ui(State.IDLE)

func _on_button_join_pressed():
	var code = input_saisie.text.to_upper().strip_edges()
	if code.length() != 6:
		status_label.text = "Code doit faire 6 caractères."
		return

	_update_ui(State.BUSY)
	var res = await LobbyManager.join_lobby(code)
	
	if res["success"]:
		status_label.text = "Connexion au salon..."
		_update_ui(State.IN_LOBBY)
	else:
		status_label.text = "Code introuvable."
		_update_ui(State.IDLE)

func _on_match_state(state: NakamaRTAPI.MatchData):
	var data = JSON.parse_string(state.data)
	if data == null: return

	match data.get("type", ""):
		"player_joined":
			if data.get("player_count", 0) >= 2:
				_start_game()
		"lobby_state":
			status_label.text = "Joueurs : %d/2" % data.get("player_count", 0)

func _on_button_copy_pressed():
	if label_code.text != "":
		DisplayServer.clipboard_set(label_code.text)
		status_label.text = "Code copié !"

func _start_game():
	status_label.text = "Lancement de la partie..."
	await get_tree().create_timer(1.5).timeout
	
	get_tree().change_scene_to_file("res://node_2d.tscn") 

func _update_ui(s):
	_state = s
	if btn_creer: btn_creer.disabled = (s != State.IDLE)
	if btn_join: btn_join.disabled = (s != State.IDLE)
	if btn_copy: btn_copy.disabled = (label_code.text == "")
