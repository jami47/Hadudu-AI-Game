extends Node2D

@export var players_per_team: int = 5
@export var move_distance: float = 8.0
@export var ai_depth: int = 1  # Reduced depth for faster, more responsive AI
@export var close_range_threshold: float = 35.0  # Distance for "very close" range (increased)
@export var catch_distance: float = 12.0  # Distance for catching the attacker (decreased)

@export var energy_min: float = 60.0
@export var energy_max: float = 100.0
@export var speed_min: float = 98.0   # Minimum speed for playability
@export var speed_max: float = 157.0  # Maximum speed for variety

@export var field_rect: Rect2 = Rect2(250, 140, 1300, 640) # x,y,w,h (centered with space for side columns)

var _rng := RandomNumberGenerator.new()
var _running := false
var _round := 0
var _turn := 0
var _frame_counter := 0  # For processing every few frames

# Game state variables
enum GameState { WAITING, ROUND_ACTIVE, POINT_SCORED }
var _game_state: GameState = GameState.WAITING
var _attacking_team: int = 0  # 0 or 1
var _defending_team: int = 1  # 1 or 0
var _attacker_index: int = 0  # Which player from attacking team is the raider
var _defenders_alerted: bool = false  # Whether defenders are rushing to catch attacker
var _team_scores: Array[int] = [0, 0]

var _panel_path := "UI/Panel"
var _button_path := "UI/Panel/StartButton"
var _round_path := "UI/Panel/RoundLabel"
var _turn_path := "UI/Panel/TurnLabel"

func _ready() -> void:
	_rng.randomize()
	_ensure_ui()
	print("[Game] UI wired: StartButton connected")
	queue_redraw()

func _process(delta: float) -> void:
	if not _running or _game_state != GameState.ROUND_ACTIVE:
		return
	
	# Always update player energy and positions
	var players := _get_players()
	for p in players:
		p.regen(delta)
		_clamp_to_field_with_restrictions(p)
	
	# Update HUD display every frame to show current stats
	_update_hud()
	
	# Process AI moves every frame for responsive defender movement
	_frame_counter += 1
	
	# Always check for defender alerts and process defender moves for responsiveness
	if not _defenders_alerted:
		_check_for_defender_alert()
	
	# Get AI moves for all players - process every frame when defenders are alerted for immediate response
	var state := _collect_state()
	
	if _defenders_alerted:
		# URGENT MODE: Process every frame for immediate attacker escape and defender chase
		_process_ai_moves(state, players)
		_check_round_end_conditions()
		_turn += 1
		_update_hud()
	elif _frame_counter >= 2:
		# NORMAL MODE: Process every 2 frames when no urgency
		_frame_counter = 0
		_process_ai_moves(state, players)
		_check_round_end_conditions()
		_turn += 1
		_update_hud()

func _ensure_ui() -> void:
	var ui = get_node_or_null("UI")
	if ui == null:
		ui = CanvasLayer.new()
		ui.name = "UI"
		add_child(ui)

	var panel = get_node_or_null(_panel_path)
	if panel == null:
		panel = Panel.new()
		panel.name = "Panel"
		ui.add_child(panel)
		panel.position = Vector2(24, 16)
		panel.custom_minimum_size = Vector2(1550, 120)
		panel.move_to_front()

	var start_btn = get_node_or_null(_button_path)
	if start_btn == null:
		start_btn = Button.new()
		start_btn.name = "StartButton"
		start_btn.text = "Start Round"
		panel.add_child(start_btn)
		start_btn.position = Vector2(12, 12)
		start_btn.pressed.connect(_on_start_round_pressed)

	var round_lb = get_node_or_null(_round_path)
	if round_lb == null:
		round_lb = Label.new()
		round_lb.name = "RoundLabel"
		panel.add_child(round_lb)
		round_lb.position = Vector2(130, 14)

	var turn_lb = get_node_or_null(_turn_path)
	if turn_lb == null:
		turn_lb = Label.new()
		turn_lb.name = "TurnLabel"
		panel.add_child(turn_lb)
		turn_lb.position = Vector2(130, 36)

	# Create side columns for team stats (outside game field)
	_create_side_columns(panel)

	_update_hud()
	queue_redraw()

func _on_start_round_pressed() -> void:
	print("[Game] Start Round pressed")
	_running = false
	_turn = 0
	_rng.randomize()
	_clear_players()
	_spawn_players()
	_build_hud_bars()
	_start_new_round()

func _clear_players() -> void:
	var plrs = get_node_or_null("Players")
	if plrs == null:
		return
	for c in plrs.get_children():
		c.queue_free()

func _spawn_players() -> void:
	var plrs = get_node_or_null("Players")
	if plrs == null:
		plrs = Node2D.new()
		plrs.name = "Players"
		add_child(plrs)
	var per_team := players_per_team
	var center_x := field_rect.position.x + field_rect.size.x * 0.5
	
	for t: int in [0, 1]:
		for i: int in range(per_team):
			var pscene := load("res://game/Player.tscn")
			var p = pscene.instantiate()
			p.player_id = i
			p.team = t
			p.max_energy = _rng.randf_range(energy_min, energy_max)
			# Create more natural speed variation system
			var base_speed: float = 125.0  # Central speed value
			
			# Generate player-specific speed with wider, more realistic distribution
			var speed_variation: float = _rng.randf_range(-25.0, 25.0)  # ±25 speed difference
			var secondary_variation: float = _rng.randf_range(-8.0, 8.0)  # Additional randomness
			
			# Apply team-based slight bias for balance (subtle, not game-breaking)
			var team_bias: float = 0.0
			if t == _attacking_team:
				team_bias = _rng.randf_range(-2.0, 4.0)  # Slight attacking advantage sometimes
			else:
				team_bias = _rng.randf_range(-3.0, 3.0)  # More balanced defending range
			
			# Calculate final speed with all factors
			var calculated_speed: float = base_speed + speed_variation + secondary_variation + team_bias
			
			# Ensure reasonable speed bounds with some extreme outliers allowed
			p.base_speed = clamp(calculated_speed, 95.0, 160.0)
			p.energy = p.max_energy
			p.speed = p.base_speed
			
			# Position players randomly within their respective courts for fair gameplay
			var y := _rng.randi_range(int(field_rect.position.y)+40, int(field_rect.position.y+field_rect.size.y)-40)
			var x: float
			
			# Calculate court boundaries
			var court_width: float = (center_x - field_rect.position.x)
			var min_distance_from_center: float = 80.0  # Minimum distance from center line
			var max_distance_from_center: float = court_width - 50.0  # Maximum distance (leave some border)
			
			if t == 0:  # Team 0 on left side
				# Random distance from center line within left court
				var distance_from_center: float = _rng.randf_range(min_distance_from_center, max_distance_from_center)
				x = center_x - distance_from_center
			else:  # Team 1 on right side
				# Random distance from center line within right court  
				var distance_from_center: float = _rng.randf_range(min_distance_from_center, max_distance_from_center)
				x = center_x + distance_from_center
			
			p.global_position = Vector2(x, y)
			var color := Color(0.2,0.6,1.0,1.0) if t == 0 else Color(1.0,0.4,0.3,1.0)
			var tex := Util.create_circle_texture(12.0, color)  # Slightly larger circles
			p.set_texture(tex)
			plrs.add_child(p)
			print("[Game] Spawned Team %d Player %d at (%.1f, %.1f) E=%.1f S=%.1f" % [t, i, p.global_position.x, p.global_position.y, p.energy, p.speed])
	
	# Update the side tables with new player stats
	_build_hud_bars()

func _create_side_columns(panel: Control) -> void:
	# Remove old stats containers if exist
	var old_left = panel.get_node_or_null("LeftStats")
	var old_right = panel.get_node_or_null("RightStats")
	var old_hud = panel.get_node_or_null("HUDRow")
	if old_left:
		old_left.queue_free()
	if old_right:
		old_right.queue_free()
	if old_hud:
		old_hud.queue_free()
	
	# Calculate vertical center position for tables
	var field_center_y = field_rect.position.y + field_rect.size.y / 2
	var table_start_y = field_center_y - 80  # Center the table vertically
	
	# Create left side table for Team 0
	var left_main_container = VBoxContainer.new()
	left_main_container.name = "LeftStats"
	panel.add_child(left_main_container)
	left_main_container.position = Vector2(50, table_start_y - 40)  # Position headers above table (symmetric distance from field)
	
	# Headers for left side (S and E outside table)
	var left_header_container = HBoxContainer.new()
	left_main_container.add_child(left_header_container)
	
	var left_spacer = Control.new()
	left_spacer.custom_minimum_size = Vector2(30, 25)
	left_header_container.add_child(left_spacer)
	
	var left_s_header = Label.new()
	left_s_header.text = "S"
	left_s_header.add_theme_font_size_override("font_size", 18)
	left_s_header.custom_minimum_size = Vector2(50, 25)
	left_header_container.add_child(left_s_header)
	
	var left_e_header = Label.new()
	left_e_header.text = "E"  
	left_e_header.add_theme_font_size_override("font_size", 18)
	left_e_header.custom_minimum_size = Vector2(50, 25)
	left_header_container.add_child(left_e_header)
	
	# Create table container for Team 0 with background
	var left_table = Panel.new()
	left_table.name = "Team0Table"
	left_main_container.add_child(left_table)
	left_table.custom_minimum_size = Vector2(130, 170)
	
	# Add background color for Team 0 table
	var left_stylebox = StyleBoxFlat.new()
	left_stylebox.bg_color = Color(0.15, 0.25, 0.4, 0.8)  # Blue-ish background for Team 0
	left_stylebox.border_width_left = 2
	left_stylebox.border_width_right = 2
	left_stylebox.border_width_top = 2
	left_stylebox.border_width_bottom = 2
	left_stylebox.border_color = Color.WHITE
	left_table.add_theme_stylebox_override("panel", left_stylebox)
	
	# Create right side table for Team 1
	var right_main_container = VBoxContainer.new()
	right_main_container.name = "RightStats"
	panel.add_child(right_main_container)
	right_main_container.position = Vector2(1580, table_start_y - 40)  # Position headers above table
	
	# Headers for right side (S and E outside table)
	var right_header_container = HBoxContainer.new()
	right_main_container.add_child(right_header_container)
	
	var right_spacer = Control.new()
	right_spacer.custom_minimum_size = Vector2(30, 25)
	right_header_container.add_child(right_spacer)
	
	var right_s_header = Label.new()
	right_s_header.text = "S"
	right_s_header.add_theme_font_size_override("font_size", 18)
	right_s_header.custom_minimum_size = Vector2(50, 25)
	right_header_container.add_child(right_s_header)
	
	var right_e_header = Label.new()
	right_e_header.text = "E"
	right_e_header.add_theme_font_size_override("font_size", 18)
	right_e_header.custom_minimum_size = Vector2(50, 25)
	right_header_container.add_child(right_e_header)
	
	# Create table container for Team 1 with background
	var right_table = Panel.new()
	right_table.name = "Team1Table"
	right_main_container.add_child(right_table)
	right_table.custom_minimum_size = Vector2(130, 170)
	
	# Add background color for Team 1 table  
	var right_stylebox = StyleBoxFlat.new()
	right_stylebox.bg_color = Color(0.4, 0.15, 0.15, 0.8)  # Red-ish background for Team 1
	right_stylebox.border_width_left = 2
	right_stylebox.border_width_right = 2
	right_stylebox.border_width_top = 2
	right_stylebox.border_width_bottom = 2
	right_stylebox.border_color = Color.WHITE
	right_table.add_theme_stylebox_override("panel", right_stylebox)
	
	# Add table content for Team 0 (left side)
	var left_grid = VBoxContainer.new()
	left_table.add_child(left_grid)
	left_grid.position = Vector2(5, 5)
	
	for i in range(players_per_team):
		var left_row = HBoxContainer.new()
		left_grid.add_child(left_row)
		left_row.add_theme_constant_override("separation", 2)
		
		# Player number
		var left_num = Label.new()
		left_num.text = "%d" % (i + 1)
		left_num.add_theme_font_size_override("font_size", 18)
		left_num.add_theme_color_override("font_color", Color.WHITE)
		left_num.custom_minimum_size = Vector2(25, 32)
		left_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left_row.add_child(left_num)
		
		# Speed value
		var ls_label = Label.new()
		ls_label.name = "S_0_%d" % i
		ls_label.text = "0"
		ls_label.add_theme_font_size_override("font_size", 18)
		ls_label.add_theme_color_override("font_color", Color.WHITE)
		ls_label.custom_minimum_size = Vector2(45, 32)
		ls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left_row.add_child(ls_label)
		
		# Energy value
		var le_label = Label.new()
		le_label.name = "E_0_%d" % i
		le_label.text = "0"
		le_label.add_theme_font_size_override("font_size", 18)
		le_label.add_theme_color_override("font_color", Color.WHITE)
		le_label.custom_minimum_size = Vector2(45, 32)
		le_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left_row.add_child(le_label)
	
	# Add table content for Team 1 (right side)
	var right_grid = VBoxContainer.new()
	right_table.add_child(right_grid)
	right_grid.position = Vector2(5, 5)
	
	for i in range(players_per_team):
		var right_row = HBoxContainer.new()
		right_grid.add_child(right_row)
		right_row.add_theme_constant_override("separation", 2)
		
		# Player number
		var right_num = Label.new()
		right_num.text = "%d" % (i + 1)
		right_num.add_theme_font_size_override("font_size", 18)
		right_num.add_theme_color_override("font_color", Color.WHITE)
		right_num.custom_minimum_size = Vector2(25, 32)
		right_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right_row.add_child(right_num)
		
		# Speed value
		var rs_label = Label.new()
		rs_label.name = "S_1_%d" % i
		rs_label.text = "0"
		rs_label.add_theme_font_size_override("font_size", 18)
		rs_label.add_theme_color_override("font_color", Color.WHITE)
		rs_label.custom_minimum_size = Vector2(45, 32)
		rs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right_row.add_child(rs_label)
		
		# Energy value
		var re_label = Label.new()
		re_label.name = "E_1_%d" % i
		re_label.text = "0"
		re_label.add_theme_font_size_override("font_size", 18)
		re_label.add_theme_color_override("font_color", Color.WHITE)
		re_label.custom_minimum_size = Vector2(45, 32)
		re_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right_row.add_child(re_label)


func _build_hud_bars() -> void:
	var panel = get_node_or_null(_panel_path)
	if panel == null:
		return
	
	# Recreate side columns with fresh data
	_create_side_columns(panel)
	_update_hud()

func _update_hud() -> void:
	var round_lb = get_node_or_null(_round_path)
	var turn_lb = get_node_or_null(_turn_path)
	if round_lb:
		var status_text = ""
		match _game_state:
			GameState.WAITING:
				status_text = "Waiting to Start"
			GameState.ROUND_ACTIVE:
				status_text = "Team %d Attacking" % _attacking_team
			GameState.POINT_SCORED:
				status_text = "Point Scored!"
		round_lb.text = "Round: %d  Status: %s  Score: %d - %d" % [_round, status_text, _team_scores[0], _team_scores[1]]
	if turn_lb:
		if _game_state == GameState.ROUND_ACTIVE:
			turn_lb.text = "Turn: %d  Attacker: Player %d (Team %d)  Defenders Alerted: %s" % [_turn, _attacker_index + 1, _attacking_team, "Yes" if _defenders_alerted else "No"]
		else:
			turn_lb.text = "Turn: %d" % _turn

	# Update side column labels with current player stats
	var panel = get_node_or_null(_panel_path)
	if panel == null:
		return
	
	var label_map := {}
	for n in panel.find_children("*", "Label", true, false):
		label_map[n.name] = n
	
	var players := _get_players()
	for p in players:
		var t: int = int(p.team)
		var i: int = int(p.player_id)
		var ekey := "E_%d_%d" % [t, i]
		var skey := "S_%d_%d" % [t, i]
		
		if ekey in label_map:
			var elabel = label_map[ekey]
			elabel.text = "%d" % int(p.energy)
		
		if skey in label_map:
			var slabel = label_map[skey]
			slabel.text = "%d" % int(p.speed)

func _collect_state() -> Dictionary:
	var players_arr := []
	for p in _get_players():
		players_arr.append({
			"team": p.team,
			"id": p.player_id,
			"pos": p.global_position,
			"energy": p.energy,
			"speed": p.speed
		})
	return {
		"players": players_arr,
		"attacking_team": _attacking_team,
		"defending_team": _defending_team,
		"attacker_index": _attacker_index,
		"defenders_alerted": _defenders_alerted,
		"field_center_x": field_rect.position.x + field_rect.size.x * 0.5
	}

func _get_players() -> Array:
	var list := []
	var plrs = get_node_or_null("Players")
	if plrs == null:
		return list
	for c in plrs.get_children():
		if c.has_method("apply_move"):
			list.append(c)
	return list

func _clamp_to_field(p: Node2D) -> void:
	var r := field_rect
	var pos := p.global_position
	pos.x = clamp(pos.x, r.position.x, r.position.x + r.size.x)
	pos.y = clamp(pos.y, r.position.y, r.position.y + r.size.y)
	p.global_position = pos

func _clamp_to_field_with_restrictions(p: Node2D) -> void:
	var r := field_rect
	var pos := p.global_position
	var center_x := r.position.x + r.size.x * 0.5
	
	# Basic field boundary clamping
	pos.x = clamp(pos.x, r.position.x, r.position.x + r.size.x)
	pos.y = clamp(pos.y, r.position.y, r.position.y + r.size.y)
	
	# Enforce court restrictions during active rounds
	if _game_state == GameState.ROUND_ACTIVE:
		var is_attacker : bool = (p.team == _attacking_team and p.player_id == _attacker_index) as bool #changed to bool
		
		if not is_attacker:  # This is a defender or non-attacking player
			# All non-attackers must stay in their own court
			if p.team == 0:  # Team 0 stays on left side
				pos.x = clamp(pos.x, r.position.x, center_x)
			else:  # Team 1 stays on right side  
				pos.x = clamp(pos.x, center_x, r.position.x + r.size.x)
	
	p.global_position = pos

func _start_new_round() -> void:
	_round += 1  # Increment round counter for new rounds after points
	_game_state = GameState.ROUND_ACTIVE
	_turn = 0
	_defenders_alerted = false
	_attacker_index = _rng.randi() % players_per_team  # Random attacker from attacking team
	
	# Respawn all players in new random positions
	_clear_players()
	_spawn_players()
	_build_hud_bars()
	
	_running = true
	print("[Game] Round %d started: Team %d attacking, Player %d is the attacker" % [_round, _attacking_team, _attacker_index + 1])
	_update_hud()

func _check_for_defender_alert() -> void:
	var players := _get_players()
	var attacker := _get_attacker(players)
	if attacker == null:
		return
	
	# Variable alert distance for more unpredictable gameplay
	var dynamic_alert_range: float = close_range_threshold + _rng.randf_range(-15.0, 10.0)
	dynamic_alert_range = max(30.0, dynamic_alert_range)  # Minimum 30 units
	
	var defenders := _get_defenders(players)
	for defender in defenders:
		var distance := attacker.global_position.distance_to(defender.global_position)
		if distance <= dynamic_alert_range:
			_defenders_alerted = true
			print("[Game] Defenders alerted! Attacker got within range of Player %d" % (defender.player_id + 1))
			break

func _process_ai_moves(state: Dictionary, players: Array) -> void:
	# Process attacker move - only the designated attacker should move initially
	var attacker := _get_attacker(players)
	if attacker != null:
		var attacker_move := AI.get_attacker_move(state, _attacking_team, _attacker_index, ai_depth, move_distance, _defenders_alerted)
		if attacker_move["delta"] != Vector2.ZERO:
			_apply_player_move(attacker, attacker_move)
		else:
			# Force attacker to move towards opponent court if AI returns zero movement
			var forced_move := {"delta": Vector2(move_distance, 0) if _attacking_team == 0 else Vector2(-move_distance, 0)}
			_apply_player_move(attacker, forced_move)
			print("[Game] Forced attacker movement to prevent standstill")
	
	# Process defender moves (only if alerted and only defending team players)
	if _defenders_alerted:
		var defenders := _get_defenders(players)
		var attacker_pos := attacker.global_position if attacker else Vector2.ZERO
		
		# All defenders chase the attacker when alerted
		
		for defender in defenders:
			# Ensure all defenders move towards attacker with simplified direct approach
			var direction_to_attacker: Vector2 = (attacker_pos - defender.global_position).normalized()
			var distance_to_attacker: float = defender.global_position.distance_to(attacker_pos)
			
			# Use direct movement for more predictable chasing behavior
			if distance_to_attacker > 5.0:  # Only move if not too close
				var chase_move := {"delta": direction_to_attacker * move_distance}
				_apply_player_move(defender, chase_move)
	
	# All other players (non-attacking team members and non-designated attacker) should not move
	# They'll stay in place due to the restriction system

func _apply_player_move(player: Node2D, move: Dictionary) -> void:
	if move.has("delta") and move["delta"] != Vector2.ZERO:
		var delta_vec: Vector2 = move["delta"]
		var speedf: float = float(player.speed)
		var energy_ratio: float = float(player.energy) / max(float(player.max_energy), 1.0)
		
		# Calculate maximum allowed displacement based on player's actual speed
		var base_scale: float = 0.15  # Increased base movement scale for more responsive movement
		
		# Give attacker a speed boost when defenders are alerted (escape mode)
		var is_attacker: bool = (player.team == _attacking_team and player.player_id == _attacker_index)
		var is_defender: bool = (player.team == _defending_team and _defenders_alerted)
		
		if is_attacker and _defenders_alerted:
			# Variable escape boost based on energy and randomness for unpredictability
			var energy_factor: float = energy_ratio * 0.3  # 0.0 to 0.3 bonus
			var random_boost: float = _rng.randf_range(1.2, 1.6)  # 1.2x to 1.6x variable boost
			base_scale *= (random_boost + energy_factor)
		elif is_defender:
			# Defenders get consistent but varied chase advantage
			var chase_boost: float = _rng.randf_range(1.05, 1.25)  # 1.05x to 1.25x variable boost
			base_scale *= chase_boost
		
		var max_displacement: float = speedf * base_scale
		
		# Smooth out movement by ensuring minimum displacement
		var desired_displacement: Vector2
		if delta_vec.length() > 0.1:  # Only move if significant direction
			desired_displacement = delta_vec.normalized() * max_displacement
		else:
			desired_displacement = Vector2.ZERO
		
		# Apply energy penalty to the displacement
		var final_displacement: Vector2 = desired_displacement * clamp(energy_ratio, 0.3, 1.0)
		
		player.apply_move(final_displacement)
		_clamp_to_field_with_restrictions(player)

func _check_round_end_conditions() -> void:
	var players := _get_players()
	var attacker := _get_attacker(players)
	if attacker == null:
		return
	
	var center_x := field_rect.position.x + field_rect.size.x * 0.5
	var attacker_pos := attacker.global_position
	
	# Check if attacker was caught by any defender
	if _defenders_alerted:
		var defenders := _get_defenders(players)
		for defender in defenders:
			var distance := attacker_pos.distance_to(defender.global_position)
			if distance <= catch_distance:
				# Defending team gets the point
				_award_point(_defending_team, "Attacker caught by Player %d" % (defender.player_id + 1))
				return
	
	# Check if attacker returned to their original court safely
	if _attacking_team == 0 and attacker_pos.x < center_x:
		# Team 0 attacker returned to left side
		if _defenders_alerted:  # Only award point if they actually engaged
			_award_point(_attacking_team, "Attacker returned safely")
	elif _attacking_team == 1 and attacker_pos.x > center_x:
		# Team 1 attacker returned to right side  
		if _defenders_alerted:  # Only award point if they actually engaged
			_award_point(_attacking_team, "Attacker returned safely")

func _award_point(team: int, reason: String) -> void:
	_team_scores[team] += 1
	_game_state = GameState.POINT_SCORED
	print("[Game] Point awarded to Team %d: %s" % [team, reason])
	
	# Switch attacking/defending teams for next round
	_attacking_team = 1 - _attacking_team
	_defending_team = 1 - _defending_team
	
	_update_hud()
	
	# Start next round after a brief pause using a timer
	var timer := Timer.new()
	add_child(timer)
	timer.wait_time = 2.0
	timer.one_shot = true
	timer.timeout.connect(_on_auto_start_next_round)
	timer.start()

func _on_auto_start_next_round() -> void:
	# Clean up the timer
	for child in get_children():
		if child is Timer:
			child.queue_free()
	_start_new_round()

func _get_attacker(players: Array) -> Node2D:
	for player in players:
		if player.team == _attacking_team and player.player_id == _attacker_index:
			return player
	return null

func _get_defenders(players: Array) -> Array:
	var defenders := []
	for player in players:
		if player.team == _defending_team:
			defenders.append(player)
	return defenders

func _draw() -> void:
	# Ground fill
	draw_rect(field_rect, Color(0.22, 0.22, 0.22, 1.0), true)
	# Boundary
	draw_rect(field_rect, Color.BLACK, false, 2.0)
	# Midline
	var x := field_rect.position.x + field_rect.size.x * 0.5
	draw_line(Vector2(x, field_rect.position.y),
			  Vector2(x, field_rect.position.y + field_rect.size.y),
			  Color(0.1, 0.1, 0.1, 1.0), 2.0, true)
