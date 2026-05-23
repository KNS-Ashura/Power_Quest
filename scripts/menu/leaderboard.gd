extends VBoxContainer


var template_ligne = preload("res://scenes/menu/leader_board_template.tscn")


var data_joueurs = [
	{"nom": "Robilol", "temps": "12h", "points": "9999"},
	{"nom": "PixelKing", "temps": "08h", "points": "8500"},
	{"nom": "GodotMaster", "temps": "24h", "points": "7200"},
	{"nom": "Shadow", "temps": "02h", "points": "6500"},
	{"nom": "Blainville", "temps": "15h", "points": "5000"},
	{"nom": "DarkKnight", "temps": "10h", "points": "4200"},
	{"nom": "Luna", "temps": "05h", "points": "3000"},
	{"nom": "OldPlayer", "temps": "99h", "points": "2500"}
]

func _ready():
	
	for child in get_children():
		child.queue_free()
		
	generer_classement()

func generer_classement():
	for i in range(data_joueurs.size()):
		
		var ligne = template_ligne.instantiate()
		
		
		var node_rank = ligne.get_node_or_null("Rank")
		var node_name = ligne.get_node_or_null("PlayerName")
		var node_time = ligne.get_node_or_null("PlayTime") # Le nœud qui posait problème
		var node_score = ligne.get_node_or_null("Score")

		
		if node_rank: 
			node_rank.text = str(i + 1) + "."
		
		if node_name: 
			node_name.text = data_joueurs[i]["nom"]
			
		

		if node_score: 
			node_score.text = data_joueurs[i]["points"]
		

		if node_rank:
			match i:
				0: 
					node_rank.add_theme_color_override("font_color", Color("#d4af37"))
					
					if node_name: node_name.add_theme_color_override("font_color", Color("#d4af37"))
				
				1: 
					node_rank.add_theme_color_override("font_color", Color("#4a5568"))
					if node_name: node_name.add_theme_color_override("font_color", Color("#4a5568"))
				
				2: 
					node_rank.add_theme_color_override("font_color", Color("#cd7f32"))
					if node_name: node_name.add_theme_color_override("font_color", Color("#cd7f32"))
				
				_: 
					node_rank.add_theme_color_override("font_color", Color("#3a2010")) # Marron foncé


		add_child(ligne)

	print("Leaderboard généré avec ", data_joueurs.size(), " joueurs.")
