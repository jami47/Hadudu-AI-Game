extends Node2D

@export var players_per_team: int = 5
@export var move_distance: float = 8.0
@export var ai_depth: int = 3
@export var close_range_threshold: float = 25.0  # Distance for "very close" range
@export var catch_distance: float = 15.0  # Distance for catching the attacker

@export var energy_min: float = 60.0
@export var energy_max: float = 100.0
@export var speed_min: float = 90.0
@export var speed_max: float = 160.0

@export var field_rect: Rect2 = Rect2(200, 140, 1200, 640) # x,y,w,h

var _rng := RandomNumberGenerator.new()
var _running := false
var _round := 0
var _turn := 0

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
		
	var players := _get_players()
	for p in players:
		p.regen(delta)
		_clamp_to_field_with_restrictions(p)

	# Check if we need to alert defenders (attacker got close to any defender)
	if not _defenders_alerted:
		_check_for_defender_alert()
	
	# Get AI moves for all players
	var state := _collect_state()
	_process_ai_moves(state, players)
	
	# Check win conditions
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

	var hud_row := panel.get_node_or_null("HUDRow") as HBoxContainer
	if hud_row == null:
		hud_row = HBoxContainer.new()
		hud_row.name = "HUDRow"
		panel.add_child(hud_row)
		hud_row.position = Vector2(12, 64)
		hud_row.custom_minimum_size = Vector2(1520, 44)
		hud_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var t0_box := hud_row.get_node_or_null("Team0Box") as VBoxContainer
	if t0_box == null:
		t0_box = VBoxContainer.new()
		t0_box.name = "Team0Box"
		hud_row.add_child(t0_box)
		t0_box.custom_minimum_size = Vector2(750, 44)
		var t0_title := Label.new()
		t0_title.text = "Team 0"
		t0_box.add_child(t0_title)

	var t1_box := hud_row.get_node_or_null("Team1Box") as VBoxContainer
	if t1_box == null:
		t1_box = VBoxContainer.new()
		t1_box.name = "Team1Box"
		hud_row.add_child(t1_box)
		t1_box.custom_minimum_size = Vector2(750, 44)
		var t1_title := Label.new()
		t1_title.text = "Team 1"
		t1_box.add_child(t1_title)

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
			p.base_speed = _rng.randf_range(speed_min, speed_max)
			p.energy = p.max_energy
			p.speed = p.base_speed
			
			# Position players in their respective courts (team boxes)
			var y := _rng.randi_range(int(field_rect.position.y)+40, int(field_rect.position.y+field_rect.size.y)-40)
			var x: float
			if t == 0:  # Team 0 on left side
				x = field_rect.position.x + 60 + i * 30  # Spread players in their court
			else:  # Team 1 on right side
				x = center_x + 60 + i * 30  # Spread players in their court
			
			p.global_position = Vector2(x, y)
			var color := Color(0.2,0.6,1.0,1.0) if t == 0 else Color(1.0,0.4,0.3,1.0)
			var tex := Util.create_circle_texture(12.0, color)  # Slightly larger circles
			p.set_texture(tex)
			plrs.add_child(p)
			print("[Game] Spawned Team %d Player %d at (%.1f, %.1f) E=%.1f S=%.1f" % [t, i, p.global_position.x, p.global_position.y, p.energy, p.speed])

func _hud_add_player_row(dst: VBoxContainer, team_id: int, player_idx: int) -> void:
	var hb := HBoxContainer.new()
	hb.custom_minimum_size = Vector2(740, 24)

	var lbl := Label.new()
	lbl.text = "P%d:" % player_idx
	lbl.custom_minimum_size = Vector2(36, 24)

	var ebar := ProgressBar.new()
	ebar.name = "E_%d_%d" % [team_id, player_idx]
	ebar.max_value = 100.0
	ebar.value = 0.0
	ebar.custom_minimum_size = Vector2(340, 20)
	ebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var sbar := ProgressBar.new()
	sbar.name = "S_%d_%d" % [team_id, player_idx]
	sbar.max_value = 200.0
	sbar.value = 0.0
	sbar.custom_minimum_size = Vector2(320, 20)
	sbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	hb.add_child(lbl)
	hb.add_child(ebar)
	hb.add_child(sbar)
	dst.add_child(hb)


func _build_hud_bars() -> void:
	var panel = get_node_or_null(_panel_path)
	if panel == null:
		return
	var hud_row := panel.get_node_or_null("HUDRow") as HBoxContainer
	if hud_row == null:
		return

	for box_name in ["Team0Box", "Team1Box"]:
		var old = hud_row.get_node_or_null(box_name)
		if old:
			old.queue_free()

	var t0_box := VBoxContainer.new()
	t0_box.name = "Team0Box"
	hud_row.add_child(t0_box)
	var t0_title := Label.new()
	t0_title.text = "Team 0"
	t0_box.add_child(t0_title)

	var t1_box := VBoxContainer.new()
	t1_box.name = "Team1Box"
	hud_row.add_child(t1_box)
	var t1_title := Label.new()
	t1_title.text = "Team 1"
	t1_box.add_child(t1_title)


	for i: int in range(players_per_team):
		_hud_add_player_row(t0_box, 0, i)
		_hud_add_player_row(t1_box, 1, i)


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

	var panel = get_node_or_null(_panel_path)
	if panel == null:
		return
	var bar_map := {}
	for n in panel.find_children("*", "ProgressBar", true, false):
		bar_map[n.name] = n
	var players := _get_players()
	for p in players:
		var t: int = int(p.team)
		var i: int = int(p.player_id)
		var ekey := "E_%d_%d" % [t, i]
		var skey := "S_%d_%d" % [t, i]
		if ekey in bar_map:
			var ebar = bar_map[ekey]
			ebar.value = (p.energy / max(p.max_energy, 1.0)) * 100.0
		if skey in bar_map:
			var sbar = bar_map[skey]
			sbar.value = p.speed

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
	
	var defenders := _get_defenders(players)
	for defender in defenders:
		var distance := attacker.global_position.distance_to(defender.global_position)
		if distance <= close_range_threshold:
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
		for defender in defenders:
			# Only move defenders from the defending team
			if defender.team == _defending_team:
				var defender_move := AI.get_defender_move(state, _defending_team, defender.player_id, ai_depth, move_distance, attacker_pos)
				_apply_player_move(defender, defender_move)
	
	# All other players (non-attacking team members and non-designated attacker) should not move
	# They'll stay in place due to the restriction system

func _apply_player_move(player: Node2D, move: Dictionary) -> void:
	if move.has("delta") and move["delta"] != Vector2.ZERO:
		var delta_vec: Vector2 = move["delta"]
		var speedf: float = float(player.speed)
		var energy_ratio: float = float(player.energy) / max(float(player.max_energy), 1.0)
		
		# Calculate maximum allowed displacement based on player's actual speed
		var max_displacement: float = speedf * 0.05  # Scale factor to control speed
		var desired_displacement: Vector2 = delta_vec.normalized() * max_displacement
		
		# Apply energy penalty to the displacement
		var final_displacement: Vector2 = desired_displacement * clamp(energy_ratio, 0.25, 1.0)
		
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
