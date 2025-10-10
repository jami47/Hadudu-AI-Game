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

static func get_best_move(state: Dictionary, team: int, depth: int, step_size: float) -> Dictionary:
	var alpha := -INF
	var beta := INF
	var best := {"player": -1, "delta": Vector2.ZERO, "score": -INF}
	var moves := _generate_moves(state, team, step_size)
	for m in moves:
		var s2 := _apply_move(state, m)
		var sc := _min_value(s2, _opponent(team), depth - 1, alpha, beta, step_size)
		if sc > best["score"]:
			best = {"player": m["player"], "delta": m["delta"], "score": sc}
		alpha = max(alpha, sc)
	return best

static func _max_value(state: Dictionary, team: int, depth: int, alpha: float, beta: float, step: float) -> float:
	if depth <= 0:
		return _heuristic(state, team)
	var v := -INF
	for m in _generate_moves(state, team, step):
		var s2 := _apply_move(state, m)
		v = max(v, _min_value(s2, _opponent(team), depth - 1, alpha, beta, step))
		if v >= beta:
			return v
		alpha = max(alpha, v)
	return v

static func _min_value(state: Dictionary, team: int, depth: int, alpha: float, beta: float, step: float) -> float:
	if depth <= 0:
		return _heuristic(state, _opponent(team)) * -1.0
	var v := INF
	for m in _generate_moves(state, team, step):
		var s2 := _apply_move(state, m)
		v = min(v, _max_value(s2, _opponent(team), depth - 1, alpha, beta, step))
		if v <= alpha:
			return v
		beta = min(beta, v)
	return v

static func _opponent(t: int) -> int:
	return 1 - (t & 1)

static func _generate_moves(state: Dictionary, team: int, step: float) -> Array:
	var arr: Array = []
	var dirs := _directions(step)
	for i in range(state["players"].size()):
		var p: Dictionary = state["players"][i]
		if int(p.get("team", 0)) != team:
			continue
		for d in dirs:
			arr.append({"player": i, "delta": d})
	return arr

static func _apply_move(state: Dictionary, move: Dictionary) -> Dictionary:
	var s2 := {"players": []}
	var idx := int(move["player"])
	var delta := move["delta"] as Vector2
	for i in range(state["players"].size()):
		var p: Dictionary = state["players"][i].duplicate()
		if i == idx:
			var pos := (p.get("pos") as Vector2) + delta
			p["pos"] = pos
			p["energy"] = max(0.0, float(p.get("energy", 0.0)) - delta.length() * 0.1)
		s2["players"].append(p)
	return s2

static func _heuristic(state: Dictionary, team: int) -> float:
	var players: Array = state["players"]
	if players.is_empty():
		return 0.0
	var min_x := INF
	var max_x := -INF
	for p in players:
		var pos := p.get("pos", Vector2.ZERO) as Vector2
		min_x = min(min_x, pos.x)
		max_x = max(max_x, pos.x)
	var mid_x := (min_x + max_x) * 0.5

	var score := 0.0
	for p in players:
		var t := int(p.get("team", 0))
		var pos := p.get("pos", Vector2.ZERO) as Vector2
		var energy := float(p.get("energy", 0.0))
		if t == team:
			score += (pos.x - mid_x) * 0.01
			score += energy * 0.02
			var d := _nearest_opponent_distance(players, p)
			score += clamp((40.0 - d) * -0.01, -1.0, 1.0)
		else:
			score -= (pos.x - mid_x) * 0.01
			score -= energy * 0.02
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
