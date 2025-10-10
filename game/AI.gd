extends Node
class_name AI

static func _directions(step: float) -> Array[Vector2]:
	return [
		Vector2.ZERO,
		Vector2(step, 0), Vector2(-step, 0),
		Vector2(0, step), Vector2(0, -step),
		Vector2(step, step), Vector2(step, -step),
		Vector2(-step, step), Vector2(-step, -step),
	]

# Get move for attacking player (raider)
static func get_attacker_move(state: Dictionary, team: int, attacker_id: int, depth: int, step_size: float, defenders_alerted: bool) -> Dictionary:
	var alpha := -INF
	var beta := INF
	var best := {"delta": Vector2.ZERO, "score": -INF}
	var moves := _generate_attacker_moves(state, team, attacker_id, step_size, defenders_alerted)
	
	for move in moves:
		var new_state := _apply_attacker_move(state, team, attacker_id, move)
		var score := _min_value_attacker(new_state, team, depth - 1, alpha, beta, step_size, defenders_alerted)
		if score > best["score"]:
			best = {"delta": move, "score": score}
		alpha = max(alpha, score)
		if beta <= alpha:
			break
	return best

# Get move for defending player
static func get_defender_move(state: Dictionary, team: int, defender_id: int, depth: int, step_size: float, attacker_pos: Vector2) -> Dictionary:
	var alpha := -INF
	var beta := INF
	var best := {"delta": Vector2.ZERO, "score": -INF}
	var moves := _generate_defender_moves(state, team, defender_id, step_size, attacker_pos)
	
	for move in moves:
		var new_state := _apply_defender_move(state, team, defender_id, move)
		var score := _min_value_defender(new_state, team, depth - 1, alpha, beta, step_size, attacker_pos)
		if score > best["score"]:
			best = {"delta": move, "score": score}
		alpha = max(alpha, score)
		if beta <= alpha:
			break
	return best

# Minimax for attacker (trying to maximize score)
static func _max_value_attacker(state: Dictionary, team: int, depth: int, alpha: float, beta: float, step: float, defenders_alerted: bool) -> float:
	if depth <= 0:
		return _attacker_heuristic(state, team, defenders_alerted)
	var v := -INF
	var moves := _generate_attacker_moves(state, team, 0, step, defenders_alerted)  # Assuming attacker_id is tracked in state
	for move in moves:
		var new_state := _apply_attacker_move(state, team, 0, move)
		v = max(v, _min_value_attacker(new_state, team, depth - 1, alpha, beta, step, defenders_alerted))
		if v >= beta:
			return v
		alpha = max(alpha, v)
	return v

static func _min_value_attacker(state: Dictionary, team: int, depth: int, alpha: float, beta: float, step: float, defenders_alerted: bool) -> float:
	if depth <= 0:
		return _attacker_heuristic(state, team, defenders_alerted)
	var v := INF
	var moves := _generate_attacker_moves(state, team, 0, step, defenders_alerted)
	for move in moves:
		var new_state := _apply_attacker_move(state, team, 0, move)
		v = min(v, _max_value_attacker(new_state, team, depth - 1, alpha, beta, step, defenders_alerted))
		if v <= alpha:
			return v
		beta = min(beta, v)
	return v

# Minimax for defender (trying to maximize chance of catching attacker)
static func _max_value_defender(state: Dictionary, team: int, depth: int, alpha: float, beta: float, step: float, attacker_pos: Vector2) -> float:
	if depth <= 0:
		return _defender_heuristic(state, team, attacker_pos)
	var v := -INF
	var moves := _generate_defender_moves(state, team, 0, step, attacker_pos)
	for move in moves:
		var new_state := _apply_defender_move(state, team, 0, move)
		v = max(v, _min_value_defender(new_state, team, depth - 1, alpha, beta, step, attacker_pos))
		if v >= beta:
			return v
		alpha = max(alpha, v)
	return v

static func _min_value_defender(state: Dictionary, team: int, depth: int, alpha: float, beta: float, step: float, attacker_pos: Vector2) -> float:
	if depth <= 0:
		return _defender_heuristic(state, team, attacker_pos)
	var v := INF
	var moves := _generate_defender_moves(state, team, 0, step, attacker_pos)
	for move in moves:
		var new_state := _apply_defender_move(state, team, 0, move)
		v = min(v, _max_value_defender(new_state, team, depth - 1, alpha, beta, step, attacker_pos))
		if v <= alpha:
			return v
		beta = min(beta, v)
	return v

static func _opponent(t: int) -> int:
	return 1 - (t & 1)

# Generate moves for attacker
static func _generate_attacker_moves(state: Dictionary, team: int, attacker_id: int, step: float, defenders_alerted: bool) -> Array[Vector2]:
	var moves: Array[Vector2] = []
	var dirs := _directions(step)
	
	# If defenders are not alerted, prioritize getting close to them
	# If defenders are alerted, prioritize returning to own court
	for direction in dirs:
		moves.append(direction)
	
	return moves

# Generate moves for defender  
static func _generate_defender_moves(state: Dictionary, team: int, defender_id: int, step: float, attacker_pos: Vector2) -> Array[Vector2]:
	var moves: Array[Vector2] = []
	var dirs := _directions(step)
	
	# Defenders should move towards the attacker
	for direction in dirs:
		moves.append(direction)
	
	return moves

static func _apply_attacker_move(state: Dictionary, team: int, attacker_id: int, move: Vector2) -> Dictionary:
	var new_state := {"players": []}
	for i in range(state["players"].size()):
		var p: Dictionary = state["players"][i].duplicate()
		if int(p.get("team", 0)) == team and int(p.get("id", 0)) == attacker_id:
			var pos := (p.get("pos") as Vector2) + move
			p["pos"] = pos
			p["energy"] = max(0.0, float(p.get("energy", 0.0)) - move.length() * 0.1)
		new_state["players"].append(p)
	return new_state

static func _apply_defender_move(state: Dictionary, team: int, defender_id: int, move: Vector2) -> Dictionary:
	var new_state := {"players": []}
	for i in range(state["players"].size()):
		var p: Dictionary = state["players"][i].duplicate()
		if int(p.get("team", 0)) == team and int(p.get("id", 0)) == defender_id:
			var pos := (p.get("pos") as Vector2) + move
			p["pos"] = pos
			p["energy"] = max(0.0, float(p.get("energy", 0.0)) - move.length() * 0.1)
		new_state["players"].append(p)
	return new_state

# Heuristic for attacker - wants to get close to defenders or return safely
static func _attacker_heuristic(state: Dictionary, team: int, defenders_alerted: bool) -> float:
	var players: Array = state["players"]
	if players.is_empty():
		return 0.0
	
	var attacker: Dictionary
	var defenders: Array = []
	var field_center_x := 700.0  # Approximate field center
	
	# Find attacker and defenders
	for p in players:
		if int(p.get("team", 0)) == team:
			attacker = p
		else:
			defenders.append(p)
	
	if attacker.is_empty():
		return -1000.0
	
	var attacker_pos := attacker.get("pos", Vector2.ZERO) as Vector2
	var score := 0.0
	
	if not defenders_alerted:
		# Before defenders are alerted, try to get close to any defender
		var min_defender_distance := INF
		for defender in defenders:
			var defender_pos := defender.get("pos", Vector2.ZERO) as Vector2
			var distance := attacker_pos.distance_to(defender_pos)
			min_defender_distance = min(min_defender_distance, distance)
		
		# Reward getting close to defenders (closer is better)
		score += (50.0 - min_defender_distance) * 2.0
		
		# Encourage moving into opponent's territory
		if team == 0:  # Team 0, encourage moving right
			score += (attacker_pos.x - field_center_x) * 0.5
		else:  # Team 1, encourage moving left
			score += (field_center_x - attacker_pos.x) * 0.5
	else:
		# After defenders are alerted, prioritize returning to own court
		if team == 0:  # Team 0, want to return to left side
			score += (field_center_x - attacker_pos.x) * 3.0
		else:  # Team 1, want to return to right side
			score += (attacker_pos.x - field_center_x) * 3.0
		
		# Penalty for being close to defenders when they're alerted
		for defender in defenders:
			var defender_pos := defender.get("pos", Vector2.ZERO) as Vector2
			var distance := attacker_pos.distance_to(defender_pos)
			score -= max(0.0, (30.0 - distance)) * 5.0  # Heavy penalty for being close
	
	# Energy consideration
	var energy := float(attacker.get("energy", 0.0))
	score += energy * 0.1
	
	return score

# Heuristic for defender - wants to catch the attacker
static func _defender_heuristic(state: Dictionary, team: int, attacker_pos: Vector2) -> float:
	var players: Array = state["players"]
	if players.is_empty():
		return 0.0
	
	var defender: Dictionary
	for p in players:
		if int(p.get("team", 0)) == team:
			defender = p
			break
	
	if defender.is_empty():
		return -1000.0
	
	var defender_pos := defender.get("pos", Vector2.ZERO) as Vector2
	var distance_to_attacker := defender_pos.distance_to(attacker_pos)
	
	var score := 0.0
	
	# Primary goal: get as close as possible to the attacker
	score += (100.0 - distance_to_attacker) * 10.0
	
	# Bonus for being very close (catching range)
	if distance_to_attacker <= 15.0:
		score += 1000.0
	
	# Energy consideration  
	var energy := float(defender.get("energy", 0.0))
	score += energy * 0.05
	
	return score

static func _nearest_opponent_distance(players: Array, me: Dictionary) -> float:
	var best := INF
	var my_team := int(me.get("team", 0))
	var my_pos := me.get("pos", Vector2.ZERO) as Vector2
	for p in players:
		if int(p.get("team", 0)) == my_team:
			continue
		var d := ((p.get("pos", Vector2.ZERO) as Vector2) - my_pos).length()
		if d < best:
			best = d
	return best if best < INF * 0.5 else 1000.0
