extends Node
class_name RedTeamAI

# Red Team AI Helper Functions - More aggressive and risk-taking strategy

# Minimax for attacker
static func max_value_attacker(state: Dictionary, team: int, depth: int, alpha: float, beta: float, step: float, defenders_alerted: bool) -> float:
	if depth <= 0:
		return attacker_heuristic(state, team, defenders_alerted)
	var v := -INF
	var moves := generate_attacker_moves(state, team, 0, step, defenders_alerted)
	for move in moves:
		var new_state := apply_attacker_move(state, team, 0, move)
		v = max(v, min_value_attacker(new_state, team, depth - 1, alpha, beta, step, defenders_alerted))
		if v >= beta:
			return v
		alpha = max(alpha, v)
	return v

static func min_value_attacker(state: Dictionary, team: int, depth: int, alpha: float, beta: float, step: float, defenders_alerted: bool) -> float:
	if depth <= 0:
		return attacker_heuristic(state, team, defenders_alerted)
	var v := INF
	var moves := generate_attacker_moves(state, team, 0, step, defenders_alerted)
	for move in moves:
		var new_state := apply_attacker_move(state, team, 0, move)
		v = min(v, max_value_attacker(new_state, team, depth - 1, alpha, beta, step, defenders_alerted))
		if v <= alpha:
			return v
		beta = min(beta, v)
	return v

# Minimax for defender
static func max_value_defender(state: Dictionary, team: int, depth: int, alpha: float, beta: float, step: float, attacker_pos: Vector2) -> float:
	if depth <= 0:
		return defender_heuristic(state, team, attacker_pos)
	var v := -INF
	var moves := generate_defender_moves(state, team, 0, step, attacker_pos)
	for move in moves:
		var new_state := apply_defender_move(state, team, 0, move)
		v = max(v, min_value_defender(new_state, team, depth - 1, alpha, beta, step, attacker_pos))
		if v >= beta:
			return v
		alpha = max(alpha, v)
	return v

static func min_value_defender(state: Dictionary, team: int, depth: int, alpha: float, beta: float, step: float, attacker_pos: Vector2) -> float:
	if depth <= 0:
		return defender_heuristic(state, team, attacker_pos)
	var v := INF
	var moves := generate_defender_moves(state, team, 0, step, attacker_pos)
	for move in moves:
		var new_state := apply_defender_move(state, team, 0, move)
		v = min(v, max_value_defender(new_state, team, depth - 1, alpha, beta, step, attacker_pos))
		if v <= alpha:
			return v
		beta = min(beta, v)
	return v

# Generate attacker moves - aggressive approach
static func generate_attacker_moves(state: Dictionary, team: int, attacker_id: int, step: float, defenders_alerted: bool) -> Array[Vector2]:
	var moves: Array[Vector2] = []
	var attacker_pos: Vector2 = Vector2.ZERO
	var attacker_energy: float = 100.0
	
	for player in state["players"]:
		if int(player.get("team", 0)) == team and int(player.get("id", 0)) == attacker_id:
			attacker_pos = player.get("pos", Vector2.ZERO) as Vector2
			attacker_energy = player.get("energy", 100.0) as float
			break
	
	var dirs := _directions(step)
	
	if not defenders_alerted:
		# Target closest defender aggressively
		var closest_defender_pos: Vector2 = Vector2.ZERO
		var closest_distance := INF
		
		for player in state["players"]:
			if int(player.get("team", 0)) != team:
				var def_pos := player.get("pos", Vector2.ZERO) as Vector2
				var distance := attacker_pos.distance_to(def_pos)
				if distance < closest_distance:
					closest_distance = distance
					closest_defender_pos = def_pos
		
		if closest_distance < INF:
			var scored_moves: Array = []
			var direction_to_target := (closest_defender_pos - attacker_pos).normalized()
			
			for direction in dirs:
				var new_pos := attacker_pos + direction
				var score := 0.0
				var new_distance := new_pos.distance_to(closest_defender_pos)
				score += (closest_distance - new_distance) * 18.0
				
				if new_distance < 40.0:
					score += 150.0
				if new_distance < 35.0:
					score += 250.0
				
				if direction.length() > 0:
					score += direction.normalized().dot(direction_to_target) * 10.0
				
				scored_moves.append({"move": direction, "score": score})
			
			scored_moves.sort_custom(func(a, b): return a["score"] > b["score"])
			for scored_move in scored_moves:
				moves.append(scored_move["move"])
		else:
			for direction in dirs:
				moves.append(direction)
	else:
		# Escape mode
		var direction_to_home: Vector2 = Vector2(-1, 0) if team == 0 else Vector2(1, 0)
		var scored_moves: Array = []
		
		for direction in dirs:
			var new_pos := attacker_pos + direction
			var score := 0.0
			var home_alignment := direction.normalized().dot(direction_to_home) if direction.length() > 0 else 0.0
			score += home_alignment * 25.0
			
			# Avoid defenders
			for player in state["players"]:
				if int(player.get("team", 0)) != team:
					var def_pos := player.get("pos", Vector2.ZERO) as Vector2
					var dist_to_def := new_pos.distance_to(def_pos)
					if dist_to_def < 30.0:
						score -= (30.0 - dist_to_def) * 2.0
			
			scored_moves.append({"move": direction, "score": score})
		
		scored_moves.sort_custom(func(a, b): return a["score"] > b["score"])
		for scored_move in scored_moves:
			moves.append(scored_move["move"])
	
	return moves

# Generate defender moves - coordinated interception
static func generate_defender_moves(state: Dictionary, team: int, defender_id: int, step: float, attacker_pos: Vector2) -> Array[Vector2]:
	var moves: Array[Vector2] = []
	var defender_pos: Vector2 = Vector2.ZERO
	var teammates: Array = []
	
	for player in state["players"]:
		if int(player.get("team", 0)) == team:
			if int(player.get("id", 0)) == defender_id:
				defender_pos = player.get("pos", Vector2.ZERO) as Vector2
			else:
				teammates.append(player.get("pos", Vector2.ZERO) as Vector2)
	
	var direction_to_attacker := (attacker_pos - defender_pos).normalized()
	var predicted_attacker_pos := attacker_pos + direction_to_attacker * 20.0
	var dirs := _directions(step)
	var scored_moves: Array = []
	
	for direction in dirs:
		var new_pos := defender_pos + direction
		var score := 0.0
		var dist_to_predicted := new_pos.distance_to(predicted_attacker_pos)
		var dist_to_current := new_pos.distance_to(attacker_pos)
		score += (100.0 - min(dist_to_predicted, 100.0)) * 6.0
		score += (100.0 - min(dist_to_current, 100.0)) * 10.0
		
		if teammates.size() > 0:
			var avg_teammate_dist := 0.0
			for mate_pos in teammates:
				avg_teammate_dist += new_pos.distance_to(mate_pos)
			avg_teammate_dist /= teammates.size()
			var ideal_dist := 60.0
			var dist_diff: float = abs(avg_teammate_dist - ideal_dist)
			if dist_diff < 20.0:
				score += 40.0
			elif dist_diff < 40.0:
				score += 20.0
		
		if direction.length() > 0:
			score += direction.normalized().dot(direction_to_attacker) * 8.0
		
		scored_moves.append({"move": direction, "score": score})
	
	scored_moves.sort_custom(func(a, b): return a["score"] > b["score"])
	for scored_move in scored_moves:
		moves.append(scored_move["move"])
	
	return moves

# Apply moves
static func apply_attacker_move(state: Dictionary, team: int, attacker_id: int, move: Vector2) -> Dictionary:
	var new_state := {"players": []}
	for i in range(state["players"].size()):
		var p: Dictionary = state["players"][i].duplicate()
		if int(p.get("team", 0)) == team and int(p.get("id", 0)) == attacker_id:
			p["pos"] = (p.get("pos") as Vector2) + move
			p["energy"] = max(0.0, float(p.get("energy", 0.0)) - move.length() * 0.12)
		new_state["players"].append(p)
	return new_state

static func apply_defender_move(state: Dictionary, team: int, defender_id: int, move: Vector2) -> Dictionary:
	var new_state := {"players": []}
	for i in range(state["players"].size()):
		var p: Dictionary = state["players"][i].duplicate()
		if int(p.get("team", 0)) == team and int(p.get("id", 0)) == defender_id:
			p["pos"] = (p.get("pos") as Vector2) + move
			p["energy"] = max(0.0, float(p.get("energy", 0.0)) - move.length() * 0.11)
		new_state["players"].append(p)
	return new_state

# Attacker heuristic - aggressive
static func attacker_heuristic(state: Dictionary, team: int, defenders_alerted: bool) -> float:
	var players: Array = state["players"]
	if players.is_empty():
		return 0.0
	
	var attacker: Dictionary
	var defenders: Array = []
	var field_center_x: float = state.get("field_center_x", 800.0)
	
	for p in players:
		if int(p.get("team", 0)) == team:
			attacker = p
		else:
			defenders.append(p)
	
	if attacker.is_empty() or defenders.is_empty():
		return -1000.0
	
	var attacker_pos := attacker.get("pos", Vector2.ZERO) as Vector2
	var energy := float(attacker.get("energy", 0.0))
	var score := 0.0
	
	if not defenders_alerted:
		var closest_defender_dist := INF
		for defender in defenders:
			var def_pos := defender.get("pos", Vector2.ZERO) as Vector2
			closest_defender_dist = min(closest_defender_dist, attacker_pos.distance_to(def_pos))
		
		score += (120.0 - closest_defender_dist) * 15.0
		
		if closest_defender_dist <= 35.0:
			score += 600.0
		elif closest_defender_dist <= 50.0:
			score += 350.0
		
		if team == 0:
			score += (attacker_pos.x - field_center_x) * 0.8
		else:
			score += (field_center_x - attacker_pos.x) * 0.8
		
		var border_penalty := 0.0
		if attacker_pos.x < 270.0 or attacker_pos.x > 1530.0:
			border_penalty += 80.0
		if attacker_pos.y < 160.0 or attacker_pos.y > 760.0:
			border_penalty += 60.0
		score -= border_penalty
	else:
		if team == 0:
			score += (field_center_x - attacker_pos.x) * 18.0
		else:
			score += (attacker_pos.x - field_center_x) * 18.0
		
		var distance_to_home: float = abs(attacker_pos.x - field_center_x)
		if distance_to_home < 15.0:
			score += 1200.0
		elif distance_to_home < 40.0:
			score += 600.0
		
		for defender in defenders:
			var def_pos := defender.get("pos", Vector2.ZERO) as Vector2
			var distance := attacker_pos.distance_to(def_pos)
			if distance < 15.0:
				score -= (15.0 - distance) * 12.0
	
	score += energy * 0.03
	return score

# Defender heuristic - coordinated
static func defender_heuristic(state: Dictionary, team: int, attacker_pos: Vector2) -> float:
	var players: Array = state["players"]
	if players.is_empty():
		return 0.0
	
	var defender: Dictionary
	var teammates: Array = []
	
	for p in players:
		if int(p.get("team", 0)) == team:
			if p.has("id"):
				defender = p
			else:
				teammates.append(p)
	
	if defender.is_empty():
		return -1000.0
	
	var defender_pos := defender.get("pos", Vector2.ZERO) as Vector2
	var distance_to_attacker := defender_pos.distance_to(attacker_pos)
	var energy := float(defender.get("energy", 0.0))
	var score := 0.0
	
	score += (100.0 - min(distance_to_attacker, 100.0)) * 12.0
	
	if distance_to_attacker <= 12.0:
		score += 700.0
	elif distance_to_attacker <= 18.0:
		score += 350.0
	elif distance_to_attacker <= 30.0:
		score += 100.0
	
	if energy > 70.0:
		score += 40.0
	elif energy < 25.0:
		score -= 80.0
	
	return score

static func _directions(step: float) -> Array[Vector2]:
	return [
		Vector2.ZERO,
		Vector2(step, 0), Vector2(-step, 0),
		Vector2(0, step), Vector2(0, -step),
		Vector2(step, step), Vector2(step, -step),
		Vector2(-step, step), Vector2(-step, -step),
	]
