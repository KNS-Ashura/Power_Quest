class_name AuthValidation
extends RefCounted

const EMAIL_REGEX := "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
const USERNAME_REGEX := "^[a-zA-Z0-9_]{3,20}$"
const MIN_PASSWORD_LEN := 6
const MAX_PASSWORD_LEN := 128
const MAX_EMAIL_LEN := 254
const MAX_USERNAME_LEN := 20

static var _email_re: RegEx


static func is_valid_email(email: String) -> bool:
	var e := email.strip_edges().to_lower()
	if e == "" or e.length() > MAX_EMAIL_LEN:
		return false
	if _email_re == null:
		_email_re = RegEx.new()
		_email_re.compile(EMAIL_REGEX)
	return _email_re.search(e) != null


static func is_valid_username(username: String) -> bool:
	var u := username.strip_edges()
	if u == "" or u.length() > MAX_USERNAME_LEN:
		return false
	var re := RegEx.new()
	re.compile(USERNAME_REGEX)
	return re.search(u) != null


static func is_valid_password(password: String) -> String:
	if password.length() < MIN_PASSWORD_LEN:
		return TranslationServer.translate("AUTH_PWD_TOO_SHORT").format([MIN_PASSWORD_LEN])
	if password.length() > MAX_PASSWORD_LEN:
		return TranslationServer.translate("AUTH_PWD_TOO_LONG").format([MAX_PASSWORD_LEN])
	return ""


## Values sent to Nakama via JSON (no client-side SQL concatenation).
static func sanitize_email(email: String) -> String:
	return email.strip_edges().to_lower().substr(0, MAX_EMAIL_LEN)


static func sanitize_username(username: String) -> String:
	return username.strip_edges().substr(0, MAX_USERNAME_LEN)
