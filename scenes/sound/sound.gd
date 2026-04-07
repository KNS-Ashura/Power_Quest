extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

#menu sounds
@onready var menu_1 = $Menu1
@onready var menu_2 = $Menu2
@onready var menu_3 = $Menu3

#menu func
func play_menu1():
	menu_1.play()

func play_menu2():
	menu_2.play()

func play_menu3():
	menu_3.play()
