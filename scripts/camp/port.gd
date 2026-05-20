extends "res://scripts/camp/camp.gd"

## Port sites (naval production hooks into production UI later).
func _ready() -> void:
	site_type = SiteType.PORT
	super._ready()
