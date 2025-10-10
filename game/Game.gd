extends Node2D

@export var players_per_team: int = 5
@export var round_turns_limit: int = 120
@export var move_distance: float = 8.0
@export var ai_depth: int = 2

@export var energy_min: float = 60.0
@export var energy_max: float = 100.0
@export var speed_min: float = 90.0
@export var speed_max: float = 160.0

@export var field_rect: Rect2 = Rect2(200, 140, 1200, 640) # x,y,w,h

var _rng := RandomNumberGenerator.new()
var _running := false
var _round := 0
var _turn := 0
var _active_team := 0

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
	if not _running:
		return
	var players := _get_players()
	for p in players:
		p.regen(delta)
		_clamp_to_field(p)

	var state := _collect_state()
	var team := _active_team
	var move := AI.get_best_move(state, team, ai_depth, move_distance)
	if move.has("player") and move["player"] != -1:
		var idx := int(move["player"])
		var delta_vec: Vector2 = move.get("delta", Vector2.ZERO)
		if idx >= 0 and idx < players.size():
			var pnode = players[idx]
			var speedf: float = float(pnode.speed)
			var energy_ratio: float = float(pnode.energy) / max(float(pnode.max_energy), 1.0)
			var factor: float = (speedf / 120.0) * clamp(energy_ratio, 0.25, 1.0)
			var disp: Vector2 = delta_vec * factor * 0.5
			pnode.apply_move(disp)
			_clamp_to_field(pnode)
	_turn += 1
	_active_team = 1 - _active_team
	_update_hud()
	if _turn >= round_turns_limit:
		_end_round()

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
	_round += 1
	print("[Game] Round %d starting: spawning players..." % _round)
	_running = false
	_turn = 0
	_active_team = 0
	_rng.randomize()
	_clear_players()
	_spawn_players()
	_build_hud_bars()
	_running = true

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
			var y := _rng.randi_range(int(field_rect.position.y)+20, int(field_rect.position.y+field_rect.size.y)-20)
			var x := int(field_rect.position.x) + 40 if t == 0 else int(field_rect.position.x + field_rect.size.x) - 40
			p.global_position = Vector2(x, y)
			var color := Color(0.2,0.6,1.0,1.0) if t == 0 else Color(1.0,0.4,0.3,1.0)
			var tex := Util.create_circle_texture(10.0, color)
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
		round_lb.text = "Round: %d  Status: %s" % [_round, "Running" if _running else "Stopped"]
	if turn_lb:
		turn_lb.text = "Turn: %d / %d" % [_turn, round_turns_limit]

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
	return {"players": players_arr}

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

func _end_round() -> void:
	_running = false
	var p := _get_players()
	var e0 := 0.0
	var e1 := 0.0
	var c0 := 0
	var c1 := 0
	for pl in p:
		if pl.team == 0:
			e0 += pl.energy
			c0 += 1
		else:
			e1 += pl.energy
			c1 += 1
	var avg0 := 0.0 if c0 == 0 else e0 / c0
	var avg1 := 0.0 if c1 == 0 else e1 / c1
	print("[Game] Round finished. Summary: team0_avg_energy=%.1f, team1_avg_energy=%.1f" % [avg0, avg1])
	_update_hud()

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
