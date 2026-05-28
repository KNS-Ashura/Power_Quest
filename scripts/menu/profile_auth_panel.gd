extends Node2D

@onready var _logout_button: BaseButton = $Deconnexion
@onready var _status_label: Label = $TextureRect/Label
@onready var _pseudo_label: Label = $SectionInfo/Pseudo
@onready var _winrate_label: Label = $StatsDroite/Fond4/NbrWinrate
@onready var _matches_label: Label = $StatsDroite/Fond5/NbrMatchs
@onready var _time_label: Label = $StatsDroite/Fond6/NbrApm

var _auth_panel: VBoxContainer
var _email_input: LineEdit
var _username_input: LineEdit
var _password_input: LineEdit


func _ready() -> void:
	_build_auth_panel()
	_logout_button.pressed.connect(_on_logout_pressed)
	NetworkSession.auth_ready.connect(_refresh_profile_ui)
	NetworkSession.auth_failed.connect(_on_auth_failed)
	NetworkSession.session_closed.connect(_on_session_closed)
	NetworkSession.profile_updated.connect(_on_profile_updated)
	_refresh_profile_ui()


func _build_auth_panel() -> void:
	_auth_panel = VBoxContainer.new()
	_auth_panel.name = "AuthPanel"
	_auth_panel.position = Vector2(385, 445)
	_auth_panel.custom_minimum_size = Vector2(220, 130)
	_auth_panel.add_theme_constant_override("separation", 4)
	add_child(_auth_panel)

	_email_input = LineEdit.new()
	_email_input.placeholder_text = "Email"
	_auth_panel.add_child(_email_input)

	_username_input = LineEdit.new()
	_username_input.placeholder_text = "Pseudo (inscription)"
	_auth_panel.add_child(_username_input)

	_password_input = LineEdit.new()
	_password_input.placeholder_text = "Mot de passe"
	_password_input.secret = true
	_auth_panel.add_child(_password_input)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	_auth_panel.add_child(buttons)

	var login_btn := Button.new()
	login_btn.text = "Se connecter"
	login_btn.pressed.connect(_on_login_pressed)
	buttons.add_child(login_btn)

	var register_btn := Button.new()
	register_btn.text = "Créer compte"
	register_btn.pressed.connect(_on_register_pressed)
	buttons.add_child(register_btn)


func _on_login_pressed() -> void:
	_status_label.text = "Connexion..."
	NetworkSession.login_account(_email_input.text, _password_input.text)


func _on_register_pressed() -> void:
	_status_label.text = "Inscription..."
	NetworkSession.register_account(_email_input.text, _password_input.text, _username_input.text)


func _on_logout_pressed() -> void:
	NetworkSession.logout_account()


func _refresh_profile_ui() -> void:
	var logged := NetworkSession.is_account_logged_in()
	_auth_panel.visible = not logged
	_logout_button.visible = logged
	if not logged:
		_status_label.text = "Connecte-toi pour jouer en ligne."
		_pseudo_label.text = "NON CONNECTE"
		_winrate_label.text = "--"
		_matches_label.text = "--"
		_time_label.text = "--"
		return
	NetworkSession.request_player_profile()
	NetworkSession.request_leaderboard()
	_status_label.text = "Connecté"
	_pseudo_label.text = NetworkSession.account_username


func _on_profile_updated(profile: Dictionary) -> void:
	if not NetworkSession.is_account_logged_in():
		return
	_pseudo_label.text = str(profile.get("username", NetworkSession.account_username))
	_winrate_label.text = "%.1f%%" % float(profile.get("winrate", 0.0))
	_matches_label.text = str(int(profile.get("games", 0)))
	var total_sec := int(profile.get("total_seconds", 0))
	_time_label.text = _format_time(total_sec)
	_status_label.text = "Connecté"


func _on_auth_failed(message: String) -> void:
	_status_label.text = message


func _on_session_closed() -> void:
	_refresh_profile_ui()


func _format_time(total_sec: int) -> String:
	var h := total_sec / 3600
	var m := (total_sec % 3600) / 60
	return "%02dh%02d" % [h, m]
