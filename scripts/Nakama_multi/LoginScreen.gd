extends Control

@onready var signup_email = %LineEdit_Email
@onready var signup_pass = %LineEdit_Password
@onready var signup_user = %LineEdit_Username
@onready var signup_status = %Label_Status
@onready var btn_signup = %Button_login

@onready var login_email = %LineEdit_Email_Login
@onready var login_pass = %LineEdit_Password_Login
@onready var login_status = %Label_Status_login
@onready var btn_login = %Button_connexion


func _ready():
	signup_status.text = ""
	login_status.text = ""


func _on_button_login_pressed():
	var email = signup_email.text.strip_edges().to_lower()
	var password = signup_pass.text.strip_edges()
	var username = signup_user.text.strip_edges()

	if email == "" or password == "" or username == "":
		signup_status.text = "Tous les champs sont requis !"
		return

	_set_loading(true, "Création du compte...", signup_status)

	var res = await ServerConnection.client.authenticate_email_async(email, password, username, true)

	if res.is_exception():
		var msg = res.get_exception().message
		signup_status.text = "Erreur : " + msg
		_set_loading(false, "", signup_status)
	else:
		await _finalize_auth(res, signup_status)


func _on_button_connexion_pressed():
	var email = login_email.text.strip_edges().to_lower()
	var password = login_pass.text.strip_edges()

	if email == "" or password == "":
		login_status.text = "Email/Pass vides !"
		return

	_set_loading(true, "Connexion...", login_status)

	var res = await ServerConnection.client.authenticate_email_async(email, password, "", false)

	if res.is_exception():
		login_status.text = "Identifiants incorrects."
		_set_loading(false, "", login_status)
	else:
		await _finalize_auth(res, login_status)


func _finalize_auth(session_ready, status_label: Label) -> void:
	if session_ready == null or session_ready.is_exception():
		status_label.text = "Reponse serveur invalide."
		_set_loading(false, "", status_label)
		return

	ServerConnection.session = session_ready
	var socket_ok: bool = await ServerConnection.connect_socket()

	if socket_ok:
		_set_loading(false, "", status_label)
		get_tree().change_scene_to_file("res://Lobby.tscn")
	else:
		status_label.text = "Erreur de connexion Socket."
		_set_loading(false, "", status_label)


func _set_loading(is_loading: bool, msg: String, status_label: Label):
	if btn_signup: btn_signup.disabled = is_loading
	if btn_login: btn_login.disabled = is_loading
	if msg != "":
		status_label.text = msg
