extends Node2D

signal auth_completed

@onready var login_email: LineEdit = $LoginContainer/LoginEmail
@onready var login_password: LineEdit = $LoginContainer/LoginPassword
@onready var register_username: LineEdit = $RegisterContainer/RegisterUsername
@onready var register_email: LineEdit = $RegisterContainer/RegisterEmail
@onready var register_password: LineEdit = $RegisterContainer/RegisterPassword
@onready var error_message: Label = $ErrorMessage
@onready var login_button: BaseButton = get_node_or_null("BtnLogin")
@onready var register_button: BaseButton = get_node_or_null("RegisterContainer/BtnRegister")

var _auth_pending: bool = false


func _ready() -> void:
	_show_status("")
	login_password.secret = true
	register_password.secret = true
	_set_button_clickable(login_button)
	_set_button_clickable(register_button)
	_bind_button(login_button, _on_btn_login_pressed)
	_bind_button(register_button, _on_btn_register_pressed)
	if not NetworkSession.auth_ready.is_connected(_on_auth_ready):
		NetworkSession.auth_ready.connect(_on_auth_ready)
	if not NetworkSession.auth_failed.is_connected(_on_auth_failed):
		NetworkSession.auth_failed.connect(_on_auth_failed)


func _set_button_clickable(btn: BaseButton) -> void:
	if btn == null:
		return
	btn.disabled = false
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in btn.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _bind_button(btn: BaseButton, callback: Callable) -> void:
	if btn == null:
		return
	if not btn.pressed.is_connected(callback):
		btn.pressed.connect(callback)
	if not btn.gui_input.is_connected(_on_button_gui_input.bind(callback)):
		btn.gui_input.connect(_on_button_gui_input.bind(callback))


func _on_button_gui_input(event: InputEvent, callback: Callable) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			callback.call()


func _on_btn_login_pressed() -> void:
	if _auth_pending:
		return
	var email := AuthValidation.sanitize_email(login_email.text)
	var password := login_password.text
	if email == "" or password == "":
		_show_error("Remplis l'email et le mot de passe.")
		return
	if not AuthValidation.is_valid_email(email):
		_show_error("Adresse email invalide (ex: nom@domaine.com).")
		return
	var pwd_err := AuthValidation.is_valid_password(password)
	if pwd_err != "":
		_show_error(pwd_err)
		return
	_auth_pending = true
	_show_status("Connexion en cours...", false)
	NetworkSession.login_account(email, password)


func _on_btn_register_pressed() -> void:
	if _auth_pending:
		return
	var username := AuthValidation.sanitize_username(register_username.text)
	var email := AuthValidation.sanitize_email(register_email.text)
	var password := register_password.text
	if username == "" or email == "" or password == "":
		_show_error("Remplis pseudo, email et mot de passe.")
		return
	if not AuthValidation.is_valid_email(email):
		_show_error("Adresse email invalide (ex: nom@domaine.com).")
		return
	if not AuthValidation.is_valid_username(username):
		_show_error("Pseudo invalide : 3-20 caractères, lettres/chiffres/_ uniquement.")
		return
	var pwd_err := AuthValidation.is_valid_password(password)
	if pwd_err != "":
		_show_error(pwd_err)
		return
	_auth_pending = true
	_show_status("Création du compte...", false)
	NetworkSession.register_account(email, password, username)


func _on_auth_ready() -> void:
	if not NetworkSession.is_account_logged_in():
		return
	_auth_pending = false
	_show_success("Connecté ! Redirection vers le profil...")
	auth_completed.emit()
	await get_tree().create_timer(0.2).timeout
	var book := get_parent()
	if book != null and book.has_method("_on_unconnect_auth_completed"):
		book.call_deferred("_on_unconnect_auth_completed")


func _on_auth_failed(message: String) -> void:
	_auth_pending = false
	_show_error(message)


func _show_error(text: String) -> void:
	if error_message == null:
		push_warning("[Unconnect] %s" % text)
		return
	error_message.add_theme_color_override("font_color", Color("#e53e3e"))
	error_message.text = text


func _show_success(text: String) -> void:
	if error_message == null:
		return
	error_message.add_theme_color_override("font_color", Color("#38a169"))
	error_message.text = text


func _show_status(text: String, is_error: bool = false) -> void:
	if text == "":
		error_message.text = ""
		return
	if is_error:
		_show_error(text)
	else:
		error_message.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
		error_message.text = text
