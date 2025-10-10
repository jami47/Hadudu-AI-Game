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
	var alpha: float = -INF
	var beta: float = INF
	var best: Dictionary = {"delta": Vector2.ZERO, "score": -INF}
	var moves := _generate_attacker_moves(state, team, attacker_id, step_size, defenders_alerted)
	
	if moves.is_empty():
		# Fallback: return a basic move towards opponent court
		var basic_move := Vector2(step_size, 0) if team == 0 else Vector2(-step_size, 0)
		return {"delta": basic_move, "score": 0.0}
	
	for move in moves:
		var new_state := _apply_attacker_move(state, team, attacker_id, move)
		var score := _min_value_attacker(new_state, team, depth - 1, alpha, beta, step_size, defenders_alerted)
		if score > best["score"]:
			best = {"delta": move, "score": score}
		alpha = max(alpha, score)
		if beta <= alpha:
			break
	
	# If all moves have negative infinity score, pick the first non-zero move
	if best["score"] == -INF and moves.size() > 1:
		for move in moves:
			if move != Vector2.ZERO:
				best = {"delta": move, "score": 0.0}
				break
	
	return best

# Get move for defending player
static func get_defender_move(state: Dictionary, team: int, defender_id: int, depth: int, step_size: float, attacker_pos: Vector2) -> Dictionary:
	var alpha: float = -INF
	var beta: float = INF
	var best: Dictionary = {"delta": Vector2.ZERO, "score": -INF}
	var moves := _generate_defender_moves(state, team, defender_id, step_size, attacker_pos)
	
	if moves.is_empty():
		# Fallback: move directly towards attacker
		var defender_pos: Vector2 = Vector2.ZERO
		for player in state["players"]:
			if int(player.get("team", 0)) == team and int(player.get("id", 0)) == defender_id:
				defender_pos = player.get("pos", Vector2.ZERO) as Vector2
				break
		var direction := (attacker_pos - defender_pos).normalized() * step_size
		return {"delta": direction, "score": 0.0}
	
	for move in moves:
		var new_state := _apply_defender_move(state, team, defender_id, move)
		var score := _min_value_defender(new_state, team, depth - 1, alpha, beta, step_size, attacker_pos)
		if score > best["score"]:
			best = {"delta": move, "score": score}
		alpha = max(alpha, score)
		if beta <= alpha:
			break
	
	# If all moves have negative infinity score, pick the first non-zero move that goes towards attacker
	if best["score"] == -INF and moves.size() > 1:
		for move in moves:
			if move != Vector2.ZERO:
				best = {"delta": move, "score": 0.0}
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
	
	# Find attacker's current position
	var attacker_pos: Vector2 = Vector2.ZERO
	for player in state["players"]:
		if int(player.get("team", 0)) == team and int(player.get("id", 0)) == attacker_id:
			attacker_pos = player.get("pos", Vector2.ZERO) as Vector2
			break
	
	var dirs := _directions(step)
	var field_center_x: float = state.get("field_center_x", 700.0)
	
	if not defenders_alerted:
		# AGGRESSIVE DEFENDER SEEKING - Must engage defenders, not avoid them
		var all_defenders: Array = []
		var closest_defender_pos: Vector2 = Vector2.ZERO
		var min_distance := INF
		
		# Collect all defender positions
		for player in state["players"]:
			if int(player.get("team", 0)) != team:  # This is a defender
				var defender_pos := player.get("pos", Vector2.ZERO) as Vector2
				all_defenders.append(defender_pos)
				var distance := attacker_pos.distance_to(defender_pos)
				if distance < min_distance:
					min_distance = distance
					closest_defender_pos = defender_pos
		
		if closest_defender_pos != Vector2.ZERO:
			# Prioritize moves that get closer to ANY defender
			var scored_moves: Array = []
			for direction in dirs:
				var new_pos := attacker_pos + direction
				var score := 0.0
				
				# Calculate how much closer this move gets us to the nearest defender
				var best_distance_after := INF
				for defender_pos in all_defenders:
					var dist_after := new_pos.distance_to(defender_pos)
					best_distance_after = min(best_distance_after, dist_after)
				
				# Heavy reward for moves that reduce distance to closest defender
				score += (min_distance - best_distance_after) * 10.0
				
				# Direction alignment with closest defender
				if direction.length() > 0:
					var direction_to_closest := (closest_defender_pos - attacker_pos).normalized()
					score += direction.normalized().dot(direction_to_closest) * 5.0
				
				scored_moves.append({"move": direction, "score": score})
			
			scored_moves.sort_custom(func(a, b): return a["score"] > b["score"])
			for scored_move in scored_moves:
				moves.append(scored_move["move"])
		else:
			# Fallback: move toward center of opponent court
			var center_pos := Vector2(field_center_x + (50 if team == 0 else -50), 400)
			var direction_to_center := (center_pos - attacker_pos).normalized()
			var scored_moves: Array = []
			for direction in dirs:
				var score := direction.normalized().dot(direction_to_center) if direction.length() > 0 else 0.0
				scored_moves.append({"move": direction, "score": score})
			scored_moves.sort_custom(func(a, b): return a["score"] > b["score"])
			for scored_move in scored_moves:
				moves.append(scored_move["move"])
	else:
		# URGENT ESCAPE MODE: Defenders are alerted, must return home immediately!
		var direction_to_home: Vector2
		if team == 0:  # Team 0 wants to go left (towards smaller x)
			direction_to_home = Vector2(-1, 0)
		else:  # Team 1 wants to go right (towards larger x) 
			direction_to_home = Vector2(1, 0)
		
		# Collect all defender positions for comprehensive evasion
		var all_defenders: Array = []
		for player in state["players"]:
			if int(player.get("team", 0)) != team:  # This is a defender
				var defender_pos := player.get("pos", Vector2.ZERO) as Vector2
				all_defenders.append(defender_pos)
		
		var scored_moves: Array = []
		for direction in dirs:
			# MASSIVE priority for moves toward home court
			var alignment_score := direction.normalized().dot(direction_to_home) * 100.0  # Increased from implicit 1.0
			
			# Calculate total evasion bonus from ALL defenders
			var new_pos := attacker_pos + direction
			var total_evasion_bonus := 0.0
			
			for defender_pos in all_defenders:
				var current_dist := attacker_pos.distance_to(defender_pos)
				var new_dist := new_pos.distance_to(defender_pos)
				if new_dist > current_dist:
					total_evasion_bonus += 2.0  # Increased evasion bonus per defender
				else:
					total_evasion_bonus -= 5.0  # Heavy penalty for getting closer to any defender
			
			var final_score := alignment_score + total_evasion_bonus
			scored_moves.append({"move": direction, "score": final_score})
		
		scored_moves.sort_custom(func(a, b): return a["score"] > b["score"])
		for scored_move in scored_moves:
			moves.append(scored_move["move"])
	
	return moves

# Generate moves for defender  
static func _generate_defender_moves(state: Dictionary, team: int, defender_id: int, step: float, attacker_pos: Vector2) -> Array[Vector2]:
	var moves: Array[Vector2] = []
	
	# Find defender's current position
	var defender_pos: Vector2 = Vector2.ZERO
	for player in state["players"]:
		if int(player.get("team", 0)) == team and int(player.get("id", 0)) == defender_id:
			defender_pos = player.get("pos", Vector2.ZERO) as Vector2
			break
	
	# Calculate direction towards attacker
	var direction_to_attacker := (attacker_pos - defender_pos).normalized()
	
	# Generate moves that prioritize moving towards the attacker
	var dirs := _directions(step)
	
	# Sort directions by how well they align with the direction to attacker
	var scored_moves: Array = []
	for direction in dirs:
		var alignment_score := direction.normalized().dot(direction_to_attacker)
		scored_moves.append({"move": direction, "score": alignment_score})
	
	# Sort by score (highest first - best alignment with attacker direction)
	scored_moves.sort_custom(func(a, b): return a["score"] > b["score"])
	
	# Add moves in order of preference
	for scored_move in scored_moves:
		moves.append(scored_move["move"])
	
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

# Heuristic for attacker - MUST engage defenders before trying to return
static func _attacker_heuristic(state: Dictionary, team: int, defenders_alerted: bool) -> float:
	var players: Array = state["players"]
	if players.is_empty():
		return 0.0
	
	var attacker: Dictionary
	var defenders: Array = []
	var field_center_x: float = state.get("field_center_x", 800.0)
	
	# Find attacker and all defenders
	for p in players:
		if int(p.get("team", 0)) == team:
			attacker = p
		else:
			defenders.append(p)
	
	if attacker.is_empty() or defenders.is_empty():
		return -1000.0
	
	var attacker_pos := attacker.get("pos", Vector2.ZERO) as Vector2
	var score := 0.0
	
	if not defenders_alerted:
		# PHASE 1: MUST get close to defenders - this is the PRIMARY objective
		var closest_defender_distance := INF
		var closest_defender_pos := Vector2.ZERO
		
		# Find the closest defender
		for defender in defenders:
			var defender_pos := defender.get("pos", Vector2.ZERO) as Vector2
			var distance := attacker_pos.distance_to(defender_pos)
			if distance < closest_defender_distance:
				closest_defender_distance = distance
				closest_defender_pos = defender_pos
		
		# MASSIVE reward for being close to ANY defender
		score += (100.0 - closest_defender_distance) * 10.0
		
		# Extra bonus for being very close to alerting range
		if closest_defender_distance <= 40.0:
			score += 300.0
		if closest_defender_distance <= 35.0:  # Alert threshold
			score += 500.0  # Huge bonus for triggering alert
		
		# PENALTY for moving away from defenders towards borders
		if team == 0:  # Team 0 attacking right
			# Only reward moving right if there are defenders to the right
			var defenders_to_right := false
			for defender in defenders:
				var def_pos := defender.get("pos", Vector2.ZERO) as Vector2
				if def_pos.x > attacker_pos.x:
					defenders_to_right = true
					break
			if defenders_to_right:
				score += (attacker_pos.x - field_center_x) * 0.3
			else:
				score -= (attacker_pos.x - field_center_x) * 2.0  # Penalty for going away from defenders
		else:  # Team 1 attacking left
			var defenders_to_left := false
			for defender in defenders:
				var def_pos := defender.get("pos", Vector2.ZERO) as Vector2
				if def_pos.x < attacker_pos.x:
					defenders_to_left = true
					break
			if defenders_to_left:
				score += (field_center_x - attacker_pos.x) * 0.3
			else:
				score -= (field_center_x - attacker_pos.x) * 2.0  # Penalty for going away from defenders
		
		# HUGE penalty for being near field borders without engaging defenders
		var border_penalty := 0.0
		if attacker_pos.x < 250.0 or attacker_pos.x > 1350.0:
			border_penalty += 200.0
		if attacker_pos.y < 180.0 or attacker_pos.y > 740.0:
			border_penalty += 200.0
		score -= border_penalty
		
	else:
		# PHASE 2: Defenders alerted - NOW try to return home safely
		var distance_to_home: float
		if team == 0:  # Team 0 wants to go left
			distance_to_home = attacker_pos.x - field_center_x
			score += (field_center_x - attacker_pos.x) * 15.0  # Very strong return incentive
		else:  # Team 1 wants to go right
			distance_to_home = field_center_x - attacker_pos.x
			score += (attacker_pos.x - field_center_x) * 15.0  # Very strong return incentive
		
		# Massive bonus for crossing back to safety
		if abs(distance_to_home) < 10.0:
			score += 1000.0  # Win condition bonus
		elif abs(distance_to_home) < 30.0:
			score += 500.0   # Close to safety
		
		# Avoid defenders while escaping
		for defender in defenders:
			var defender_pos := defender.get("pos", Vector2.ZERO) as Vector2
			var distance := attacker_pos.distance_to(defender_pos)
			if distance < 20.0:
				score -= (20.0 - distance) * 8.0  # Penalty for being too close during escape
	
	# Energy consideration
	var energy := float(attacker.get("energy", 0.0))
	score += energy * 0.05
	
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
	score += (90.0 - distance_to_attacker) * 8.0  # Increased urgency to chase
	
	# Graduated bonus system for being close to attacker
	if distance_to_attacker <= 12.0:  # Catching range
		score += 500.0  # High bonus for catching range
	elif distance_to_attacker <= 20.0:  # Close range
		score += 200.0  # Good bonus for being close
	elif distance_to_attacker <= 35.0:  # Medium range
		score += 50.0   # Small bonus for being in vicinity
	
	# Predict attacker movement and reward intercepting moves
	# TODO: Could add prediction logic here for smarter defenders
	
	# Energy consideration (defenders need energy to chase effectively)
	var energy := float(defender.get("energy", 0.0))
	score += energy * 0.1
	
	# Add small randomness to defender behavior
	score += randf_range(-1.0, 1.0)
	
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
