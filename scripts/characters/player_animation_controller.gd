extends RefCounted
class_name PlayerAnimationController

const DirectionUtilsRef = preload("res://scripts/common/direction_utils.gd")


static func update_animation(owner: Node) -> void:
	if not owner.has_node("AnimatedSprite2D"):
		return

	var sprite: AnimatedSprite2D = owner.get_node("AnimatedSprite2D")
	if sprite.is_playing():
		if sprite.animation.begins_with("death_"):
			return
		if sprite.animation.begins_with("attack_"):
			var combat_active: bool = owner.attack_target_node != null \
				and owner._is_valid_combat_target(owner.attack_target_node) \
				and owner.attack_target_node in owner.zone_detection.get_overlapping_bodies()
			if not combat_active:
				play_on_sprites(owner, "idle_" + owner.last_facing_direction)
			return

	if owner.velocity.length() > 5.0:
		if abs(owner.velocity.x) > abs(owner.velocity.y):
			owner.last_facing_direction = "r" if owner.velocity.x > 0 else "l"
		else:
			owner.last_facing_direction = "f" if owner.velocity.y > 0 else "b"
		play_on_sprites(owner, "run_" + owner.last_facing_direction)
	else:
		play_on_sprites(owner, "idle_" + owner.last_facing_direction)


static func play_attack_animation(owner: Node, target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	if not owner.has_node("AnimatedSprite2D"):
		return

	var sprite: AnimatedSprite2D = owner.get_node("AnimatedSprite2D")
	var dir: String = direction_from_target(owner, target.global_position)
	var anim := "attack_" + dir
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		play_on_sprites(owner, anim)


static func direction_from_target(owner: Node, target_position: Vector2) -> String:
	var delta: Vector2 = target_position - owner.global_position
	return DirectionUtilsRef.direction_from_vector(delta)


static func animated_sprites(owner: Node) -> Array[AnimatedSprite2D]:
	var sprites: Array[AnimatedSprite2D] = []
	for child in owner.get_children():
		if child is AnimatedSprite2D:
			sprites.append(child as AnimatedSprite2D)
	return sprites


static func play_on_sprites(owner: Node, anim: String, fallback: String = "") -> void:
	for sprite in animated_sprites(owner):
		if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)
		elif fallback != "" and sprite.sprite_frames and sprite.sprite_frames.has_animation(fallback):
			sprite.play(fallback)


static func play_death_animation(owner: Node) -> bool:
	if not owner.has_node("AnimatedSprite2D"):
		return false

	var sprite: AnimatedSprite2D = owner.get_node("AnimatedSprite2D")
	var anim = "death_" + owner.last_facing_direction
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		play_on_sprites(owner, anim, "idle_" + owner.last_facing_direction)
		return true
	elif sprite.sprite_frames and sprite.sprite_frames.has_animation("idle_" + owner.last_facing_direction):
		play_on_sprites(owner, "idle_" + owner.last_facing_direction)
	return false


static func configure_death_animations(owner: Node) -> void:
	if not owner.has_node("AnimatedSprite2D"):
		return

	var sprite: AnimatedSprite2D = owner.get_node("AnimatedSprite2D")
	var frames: SpriteFrames = sprite.sprite_frames
	if frames == null:
		return
	if not frames.has_animation("run_f") or frames.get_frame_count("run_f") == 0:
		return

	var run_frame: Texture2D = frames.get_frame_texture("run_f", 0)
	if not (run_frame is AtlasTexture):
		return

	var atlas_run: AtlasTexture = run_frame
	if atlas_run.atlas == null:
		return

	var base_path := atlas_run.atlas.resource_path
	if base_path == "":
		return

	var death_path := base_path.get_base_dir() + "/death.png"
	if not ResourceLoader.exists(death_path):
		return

	var death_tex := load(death_path)
	if not (death_tex is Texture2D):
		return

	var frame_size := atlas_run.region.size
	if frame_size.x <= 0 or frame_size.y <= 0:
		return

	var cols := int(floor(float(death_tex.get_width()) / frame_size.x))
	var rows := int(floor(float(death_tex.get_height()) / frame_size.y))
	if cols <= 0 or rows <= 0:
		return

	var directions: Dictionary = {
		"f": 0,
		"l": 1,
		"r": 2,
		"b": 3
	}
	var speed := frames.get_animation_speed("run_f")

	for d in directions.keys():
		var row: int = int(directions[d])
		if row >= rows:
			continue

		var anim_name: String = "death_" + d
		if frames.has_animation(anim_name):
			frames.remove_animation(anim_name)
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, false)
		frames.set_animation_speed(anim_name, speed)

		for i in range(cols):
			var a := AtlasTexture.new()
			a.atlas = death_tex
			a.region = Rect2(i * frame_size.x, row * frame_size.y, frame_size.x, frame_size.y)
			frames.add_frame(anim_name, a)
