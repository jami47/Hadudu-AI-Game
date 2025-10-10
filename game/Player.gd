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
	var cost := displacement.length() * 0.1
	energy = max(0.0, energy - cost)
	global_position += displacement

func regen(delta: float) -> void:
	energy = min(max_energy, energy + 2.0 * delta)

func is_active() -> bool:
	return energy > 1.0