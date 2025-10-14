extends Node2D
class_name Player

@export var player_id: int = 0
@export var team: int = 0
@export var max_energy: float = 100.0
@export var base_speed: float = 120.0

var energy: float = 100.0
var speed: float = 120.0

func _ready() -> void:
	energy = max_energy
	speed = base_speed
	var spr := get_node_or_null("Sprite") as Sprite2D
	if spr == null:
		spr = Sprite2D.new()
		spr.name = "Sprite"
		add_child(spr)
		print("[Player] Missing Sprite -> created for player id=%d" % player_id)
	
	# Add player number label
	var label := get_node_or_null("PlayerLabel") as Label
	if label == null:
		label = Label.new()
		label.name = "PlayerLabel"
		add_child(label)
		label.text = str(player_id + 1)  # Display 1-5 instead of 0-4
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# Position label at center of player (0,0 relative to player)
		label.position = Vector2(-6, -8)  
		label.size = Vector2(12, 16)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_font_size_override("font_size", 12)
		# Make sure label follows the player and is visible
		label.z_index = 10  # Ensure it's above the sprite

func set_texture(tex: Texture2D) -> void:
	var spr := get_node_or_null("Sprite") as Sprite2D
	if spr == null:
		spr = Sprite2D.new()
		spr.name = "Sprite"
		add_child(spr)
	spr.texture = tex
	spr.centered = true
	spr.offset = Vector2.ZERO

func apply_move(displacement: Vector2) -> void:
	var cost := displacement.length() * 0.05  # Reduced from 0.1 to 0.05 for smoother gameplay
	energy = max(0.0, energy - cost)
	global_position += displacement
	# Update label position to stay centered
	_update_label_position()

func _update_label_position() -> void:
	var label := get_node_or_null("PlayerLabel") as Label
	if label != null:
		# Keep the label centered on the player
		label.position = Vector2(-6, -8)

func regen(delta: float) -> void:
	energy = min(max_energy, energy + 3.0 * delta)  # Increased from 2.0 to 3.0 for better recovery

func is_active() -> bool:
	return energy > 1.0