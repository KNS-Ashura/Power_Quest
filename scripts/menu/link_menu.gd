extends VBoxContainer

const URL_MANUAL = "https://google.com"
const URL_GITHUB = "https://github.com/KNS-Ashura/Power_Quest.git"
const PATH_LICENSES = "https://craftpix.net/file-licenses/"
const PATH_TECH_DOC = "res://PROJECT_CONTEXT.md"


func _ready() -> void:
	$BtnLicences.pressed.connect(_on_licenses_pressed)
	$BtnManuel.pressed.connect(_on_manual_pressed)
	$BtnGithub.pressed.connect(_on_github_pressed)
	$BtnDocTech.pressed.connect(_on_tech_doc_pressed)


func _on_licenses_pressed() -> void:
	_open_resource(PATH_LICENSES)


func _on_manual_pressed() -> void:
	OS.shell_open(URL_MANUAL)


func _on_github_pressed() -> void:
	OS.shell_open(URL_GITHUB)


func _on_tech_doc_pressed() -> void:
	_open_resource(PATH_TECH_DOC)


func _open_resource(path: String) -> void:
	if path.begins_with("res://"):
		OS.shell_open(ProjectSettings.globalize_path(path))
	else:
		OS.shell_open(path)
