extends RefCounted
class_name Fuzzy

static func aggression(energy: float, max_energy: float, pos_x: float, field_mid_x: float) -> float:
	var e := 0.0
	if max_energy > 0.0:
		e = clamp(energy / max_energy, 0.0, 1.0)
	var denom := 1.0
	if abs(field_mid_x) > 1.0:
		denom = abs(field_mid_x)
	var pos_bias := 0.5 + clamp((pos_x - field_mid_x) / denom, -0.5, 0.5)
	return clamp(0.3 * e + 0.7 * pos_bias, 0.0, 1.0)